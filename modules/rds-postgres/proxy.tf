locals {
  proxy_enabled = var.proxy != null
  proxy_roles   = local.proxy_enabled ? var.proxy.role_names : toset([])
  known_roles   = setintersection(local.proxy_roles, toset(keys(var.database_roles)))
}

resource "aws_iam_role" "proxy" {
  count = local.proxy_enabled ? 1 : 0

  name = "${local.identifier}-proxy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "proxy" {
  count = local.proxy_enabled ? 1 : 0

  name = "read-role-secrets"
  role = aws_iam_role.proxy[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [for role in local.known_roles : aws_secretsmanager_secret.role[role].arn]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.data_kms_key_arn
      },
    ]
  })
}

resource "aws_db_proxy" "this" {
  count = local.proxy_enabled ? 1 : 0

  name                   = local.identifier
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy[0].arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.proxy.security_group_ids
  require_tls            = true
  idle_client_timeout    = var.proxy.idle_client_timeout

  dynamic "auth" {
    for_each = local.known_roles

    content {
      auth_scheme               = "SECRETS"
      client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
      iam_auth                  = "DISABLED"
      secret_arn                = aws_secretsmanager_secret.role[auth.key].arn
    }
  }

  tags = merge(var.tags, { Name = local.identifier })

  lifecycle {
    precondition {
      condition     = length(setsubtract(local.proxy_roles, keys(var.database_roles))) == 0
      error_message = "proxy.role_names must all be keys of database_roles."
    }
  }

  depends_on = [aws_secretsmanager_secret_version.role]
}

resource "aws_db_proxy_default_target_group" "this" {
  count = local.proxy_enabled ? 1 : 0

  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "this" {
  count = local.proxy_enabled ? 1 : 0

  db_proxy_name          = aws_db_proxy.this[0].name
  target_group_name      = aws_db_proxy_default_target_group.this[0].name
  db_instance_identifier = aws_db_instance.this.identifier
}
