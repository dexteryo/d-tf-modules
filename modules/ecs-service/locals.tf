data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  full_name    = "${var.name}-${var.environment}"
  cluster_name = element(split("/", var.cluster_arn), length(split("/", var.cluster_arn)) - 1)
  region       = data.aws_region.current.region

  tags = merge(var.tags, { Name = local.full_name })

  load_balancer_enabled = var.load_balancer != null

  containers = [
    for c in var.containers : merge(c, {
      health_check = c.health_check != null ? c.health_check : (
        var.default_health_check_path != null && c.port != null ? {
          command      = ["CMD-SHELL", "curl -fsS http://127.0.0.1:${c.port}${var.default_health_check_path} || exit 1"]
          interval     = 30
          timeout      = 5
          retries      = 3
          start_period = 0
        } : null
      )
    })
  ]

  container_definitions = [
    for c in local.containers : merge(concat(
      [{
        name                   = c.name
        image                  = c.image
        essential              = c.essential
        readonlyRootFilesystem = c.read_only_root_filesystem
        environment            = [for k in sort(keys(c.environment)) : { name = k, value = c.environment[k] }]
        secrets                = [for k in sort(keys(c.secrets)) : { name = k, valueFrom = c.secrets[k] }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.this.name
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = c.name
          }
        }
      }],
      [for _ in(c.port != null ? [1] : []) : { portMappings = [{ containerPort = c.port, protocol = "tcp" }] }],
      [for _ in(c.health_check != null ? [1] : []) : {
        healthCheck = {
          command     = c.health_check.command
          interval    = c.health_check.interval
          timeout     = c.health_check.timeout
          retries     = c.health_check.retries
          startPeriod = c.health_check.start_period
        }
      }],
      [for _ in(length(c.depends_on) > 0 ? [1] : []) : {
        dependsOn = [for d in c.depends_on : { containerName = d.container_name, condition = d.condition }]
      }],
      [for _ in(c.command != null ? [1] : []) : { command = c.command }],
      [for _ in(c.entry_point != null ? [1] : []) : { entryPoint = c.entry_point }],
      [for _ in(c.cpu != null ? [1] : []) : { cpu = c.cpu }],
      [for _ in(c.memory != null ? [1] : []) : { memory = c.memory }]
    )...)
  ]

  secret_arns = distinct(concat(
    flatten([for c in var.containers : values(c.secrets)]),
    var.extra_execution_secret_arns
  ))

  secrets_manager_arns = distinct([
    for a in local.secret_arns : join(":", slice(split(":", a), 0, min(7, length(split(":", a)))))
    if length(split(":", a)) > 2 && split(":", a)[2] == "secretsmanager"
  ])

  ssm_parameter_arns = distinct([
    for a in local.secret_arns : a
    if length(split(":", a)) > 2 && split(":", a)[2] == "ssm"
  ])

  ecr_image_matches = concat([
    for c in var.containers : regexall("^([0-9]{12})\\.dkr\\.ecr(?:-fips)?\\.([a-z0-9-]+)\\.amazonaws\\.com/([^:@]+)", c.image)
  ]...)

  ecr_repository_arns = distinct(concat(
    [for m in local.ecr_image_matches : "arn:aws:ecr:${m[1]}:${m[0]}:repository/${m[2]}"],
    var.extra_ecr_repository_arns
  ))

  execution_policy_statements = concat(
    [
      {
        Sid      = "EcrAuthorisationToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid      = "WriteServiceLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.this.arn}:*"]
      }
    ],
    length(local.ecr_repository_arns) == 0 ? [] : [{
      Sid      = "PullImages"
      Effect   = "Allow"
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
      Resource = local.ecr_repository_arns
    }],
    length(local.secrets_manager_arns) == 0 ? [] : [{
      Sid      = "ReadSecretsManagerSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.secrets_manager_arns
    }],
    length(local.ssm_parameter_arns) == 0 ? [] : [{
      Sid      = "ReadSsmParameters"
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = local.ssm_parameter_arns
    }],
    length(var.kms_key_arns) == 0 ? [] : [{
      Sid      = "DecryptSecrets"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.kms_key_arns
    }]
  )

  task_exec_statement = var.enable_execute_command ? [{
    Sid      = "EcsExecSessionChannels"
    Effect   = "Allow"
    Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    Resource = ["*"]
  }] : []
}
