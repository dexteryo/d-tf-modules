provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  secret_prefix = "example/ordering-agent/${var.environment}"
  secret_arn    = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.secret_prefix}"
}

resource "aws_kms_key" "sessions" {
  description             = "Ordering agent session table encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "sessions" {
  name          = "alias/ordering-agent-${var.environment}-sessions"
  target_key_id = aws_kms_key.sessions.key_id
}

resource "aws_dynamodb_table" "sessions" {
  name         = "ordering-agent-${var.environment}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

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
    kms_key_arn = aws_kms_key.sessions.arn
  }
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "SessionTableItems"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.sessions.arn]
  }

  statement {
    sid       = "SessionTableKey"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.sessions.arn]
  }
}

module "cluster" {
  source = "../../modules/ecs-cluster"

  name        = "ai-${var.environment}"
  environment = var.environment
}

module "ordering_agent" {
  source = "../../modules/ecs-service"

  name        = "ordering-agent"
  environment = var.environment
  cluster_arn = module.cluster.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  cpu    = 1024
  memory = 2048

  containers = [
    {
      name  = "ordering-agent"
      image = "${var.ecr_registry}/example/ordering-agent:bootstrap"
      port  = 8788
      environment = {
        MCP_URL             = "http://127.0.0.1:8787"
        SESSION_TABLE       = aws_dynamodb_table.sessions.name
        PORT                = "8788"
        NODE_ENV            = "production"
        AWS_REGION          = var.region
        MCP_REQUEST_TIMEOUT = "30000"
      }
      secrets = {
        LLM_API_KEY = "${local.secret_arn}/llm-AbCdEf:api_key::"
      }
      health_check = {
        command      = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8788/healthz || exit 1"]
        start_period = 30
      }
      depends_on = [
        { container_name = "ordering-mcp", condition = "HEALTHY" },
      ]
    },
    {
      name  = "ordering-mcp"
      image = "${var.ecr_registry}/example/ordering-mcp:bootstrap"
      environment = {
        PORT = "8787"
        HOST = "127.0.0.1"
      }
      secrets = {
        ORDERING_API_TOKEN = "${local.secret_arn}/ordering-GhIjKl"
      }
      health_check = {
        command      = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8787/healthz || exit 1"]
        start_period = 15
      }
    },
  ]

  load_balancer = {
    container_name        = "ordering-agent"
    container_port        = 8788
    listener_arn          = var.listener_arn
    host_headers          = [var.agent_host_header]
    priority              = 210
    health_check_path     = "/healthz"
    alb_security_group_id = var.alb_security_group_id
  }

  task_role_policy_json = data.aws_iam_policy_document.task.json

  autoscaling = {
    min        = 2
    max        = 6
    cpu_target = 60
  }

  desired_count = 2
}
