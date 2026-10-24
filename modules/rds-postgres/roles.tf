resource "random_password" "role" {
  for_each = var.database_roles

  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "role" {
  for_each = var.database_roles

  name                    = "${local.full_name}/db/${each.key}"
  kms_key_id              = var.data_kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, { Name = "${local.full_name}/db/${each.key}" })
}

resource "aws_secretsmanager_secret_version" "role" {
  for_each = var.database_roles

  secret_id = aws_secretsmanager_secret.role[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = random_password.role[each.key].result
    dbname   = each.value.database
    port     = 5432
  })
}
