data "aws_caller_identity" "current" {}

locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))
  root_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"

  administration_actions = [
    "kms:Create*",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
  ]

  encrypt_actions = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
  decrypt_actions = ["kms:Decrypt", "kms:DescribeKey"]

  root_statement = var.enable_iam_policy_delegation ? {
    Sid       = "EnableIamPolicies"
    Effect    = "Allow"
    Principal = { AWS = local.root_arn }
    Action    = ["kms:*"]
    Resource  = "*"
    } : {
    Sid       = "AdministerKey"
    Effect    = "Allow"
    Principal = { AWS = local.root_arn }
    Action    = local.administration_actions
    Resource  = "*"
  }

  principal_statements = concat(
    length(var.management_principals) == 0 ? [] : [{
      Sid       = "ManagementPrincipals"
      Effect    = "Allow"
      Principal = { AWS = distinct(var.management_principals) }
      Action    = local.administration_actions
      Resource  = "*"
    }],
    length(var.encrypt_principals) == 0 ? [] : [{
      Sid       = "EncryptPrincipals"
      Effect    = "Allow"
      Principal = { AWS = distinct(var.encrypt_principals) }
      Action    = local.encrypt_actions
      Resource  = "*"
    }],
    length(var.decrypt_principals) == 0 ? [] : [{
      Sid       = "DecryptPrincipals"
      Effect    = "Allow"
      Principal = { AWS = distinct(var.decrypt_principals) }
      Action    = local.decrypt_actions
      Resource  = "*"
    }],
  )

  service_statements = [
    for grant in var.service_grants : merge(
      {
        Sid       = grant.sid
        Effect    = "Allow"
        Principal = { Service = grant.service }
        Action    = grant.actions
        Resource  = "*"
      },
      grant.condition == null ? {} : {
        Condition = { (grant.condition.test) = { (grant.condition.variable) = grant.condition.values } }
      }
    )
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [local.root_statement],
      local.principal_statements,
      local.service_statements,
      var.additional_statements,
    )
  })
}

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = local.policy
  tags                    = merge(var.tags, { Name = local.full_name })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.full_name}"
  target_key_id = aws_kms_key.this.key_id
}
