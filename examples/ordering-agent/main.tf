provider "aws" {
  region = var.region
}

resource "random_password" "origin_verify" {
  length  = 48
  special = false
}

data "aws_caller_identity" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  registry      = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  secret_prefix = "example/ordering-agent/${var.environment}"
  secret_arn    = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:${local.secret_prefix}"
  agent_port    = 8788
  mcp_port      = 8787
  full_name     = "ordering-agent-${var.environment}"
}

module "tags" {
  source = "../../modules/tags"

  environment = var.environment
  service     = "ordering-agent"
  repository  = var.repository
}

module "app_key" {
  source = "../../modules/kms"

  name        = "ordering-agent"
  environment = var.environment
  name_suffix = "app"
  description = "Ordering agent ${var.environment}: images, secrets and task logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.${var.region}.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${local.account_id}:log-group:/ecs/${local.full_name}"]
    }
  }]
}

module "sessions_key" {
  source = "../../modules/kms"

  name        = "ordering-agent"
  environment = var.environment
  name_suffix = "sessions"
  description = "Ordering agent ${var.environment}: session table"
  tags        = module.tags.all_tags
}

module "alarm_key" {
  source = "../../modules/kms"

  name        = "ordering-agent"
  environment = var.environment
  name_suffix = "alarms"
  description = "Ordering agent ${var.environment}: alarm topic"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchAlarms"
    service = "cloudwatch.amazonaws.com"
    actions = ["kms:Decrypt", "kms:GenerateDataKey*"]
  }]
}

module "ecr" {
  for_each = toset(["ordering-agent", "ordering-mcp"])
  source   = "../../modules/ecr"

  name           = each.key
  create_kms_key = false
  kms_key_arn    = module.app_key.kms_key_arn
  tags           = module.tags.all_tags
}

resource "aws_dynamodb_table" "sessions" {
  name         = "${local.full_name}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  tags         = module.tags.all_tags

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = module.sessions_key.kms_key_arn
  }
}

module "cluster" {
  source = "../../modules/ecs-cluster"

  name        = "ai"
  environment = var.environment
  tags        = module.tags.all_tags
}

module "alb" {
  source = "../../modules/alb"

  name         = "ordering-agent"
  environment  = var.environment
  vpc_id       = var.vpc_id
  subnet_ids   = var.public_subnet_ids
  tags         = module.tags.all_tags
  idle_timeout = 120

  cloudfront_only = true

  listeners = {
    https = {
      port            = 443
      certificate_arn = var.certificate_arn
    }
  }

  header_forward_rules = {
    from-edge = {
      listener         = "https"
      priority         = 10
      header_name      = "X-Origin-Verify"
      target_group_arn = module.ordering_agent.target_group_arn
    }
  }

  header_values = { from-edge = random_password.origin_verify.result }

  egress_rules = {
    to-tasks = {
      description                  = "Agent port of the ordering tasks"
      from_port                    = local.agent_port
      to_port                      = local.agent_port
      referenced_security_group_id = module.task_security_group.security_group_id
    }
  }
}

module "task_security_group" {
  source = "../../modules/security-group"

  name        = "ordering-agent"
  environment = var.environment
  vpc_id      = var.vpc_id
  tags        = module.tags.all_tags

  ingress_rules = {
    from-alb = {
      description                  = "Agent port from the load balancer"
      from_port                    = local.agent_port
      to_port                      = local.agent_port
      referenced_security_group_id = module.alb.alb_security_group_id
    }
  }

  egress_rules = {
    vpc-https = {
      description = "HTTPS to the VPC endpoints"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.vpc_cidr
    }
  }
}

module "ordering_agent" {
  source = "../../modules/ecs-service"

  name               = "ordering-agent"
  environment        = var.environment
  tags               = module.tags.all_tags
  cluster_arn        = module.cluster.cluster_arn
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [module.task_security_group.security_group_id]

  cpu    = 1024
  memory = 2048

  containers = [
    {
      name  = "ordering-agent"
      image = "${local.registry}/ordering-agent:bootstrap"
      port  = local.agent_port
      environment = {
        MCP_URL             = "http://127.0.0.1:${local.mcp_port}"
        SESSION_TABLE       = aws_dynamodb_table.sessions.name
        PORT                = tostring(local.agent_port)
        NODE_ENV            = "production"
        AWS_REGION          = var.region
        MCP_REQUEST_TIMEOUT = "30000"
      }
      secrets = {
        LLM_API_KEY = "${local.secret_arn}/llm-AbCdEf:api_key::"
      }
      health_check = {
        command      = ["CMD-SHELL", "curl -fsS http://127.0.0.1:${local.agent_port}/healthz || exit 1"]
        start_period = 30
      }
      depends_on = [
        { container_name = "ordering-mcp", condition = "HEALTHY" },
      ]
    },
    {
      name  = "ordering-mcp"
      image = "${local.registry}/ordering-mcp:bootstrap"
      environment = {
        PORT = tostring(local.mcp_port)
        HOST = "127.0.0.1"
      }
      secrets = {
        ORDERING_API_TOKEN = "${local.secret_arn}/ordering-GhIjKl"
      }
      health_check = {
        command      = ["CMD-SHELL", "curl -fsS http://127.0.0.1:${local.mcp_port}/healthz || exit 1"]
        start_period = 15
      }
    },
  ]

  load_balancer = {
    container_name    = "ordering-agent"
    container_port    = local.agent_port
    vpc_id            = var.vpc_id
    listener_arn      = module.alb.listener_arns["https"]
    host_headers      = [var.agent_host_header]
    priority          = 210
    health_check_path = "/healthz"
  }

  kms_key_arns    = [module.app_key.kms_key_arn]
  log_kms_key_arn = module.app_key.kms_key_arn

  task_role_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SessionTableItems"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = [aws_dynamodb_table.sessions.arn]
      },
      {
        Sid      = "SessionTableKey"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [module.sessions_key.kms_key_arn]
      },
    ]
  })

  autoscaling = {
    min        = 2
    max        = 6
    cpu_target = 60
  }

  desired_count = 2
}

module "alarm_topic" {
  source = "../../modules/sns-topic"

  name            = "ordering-agent"
  environment     = var.environment
  tags            = module.tags.all_tags
  kms_key_arn     = module.alarm_key.kms_key_arn
  email_addresses = var.alarm_email_addresses
}

module "alarms" {
  source = "../../modules/ecs-service-alarms"

  name          = "ordering-agent"
  environment   = var.environment
  tags          = module.tags.all_tags
  cluster_name  = module.cluster.cluster_name
  service_name  = module.ordering_agent.service_name
  alarm_actions = [module.alarm_topic.topic_arn]

  load_balancer = {
    load_balancer_arn_suffix = module.alb.alb_arn_suffix
    target_group_arn_suffix  = module.ordering_agent.target_group_arn_suffix
  }
}

module "deploy_role" {
  source = "../../modules/ci-oidc-role"

  name              = "ordering-agent"
  environment       = var.environment
  tags              = module.tags.all_tags
  github_repository = var.github_repository
  oidc_provider_arn = var.oidc_provider_arn

  ecr_repository_arns = [for repository in module.ecr : repository.repository_arn]
  ecs_service_arns    = [module.ordering_agent.service_arn]
  pass_role_arns      = [module.ordering_agent.execution_role_arn, module.ordering_agent.task_role_arn]
}
