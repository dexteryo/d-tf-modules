mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name        = "ordering"
  environment = "integration"
  description = "Ordering integration: task logs and secrets"
  tags        = { Environment = "integration" }
}

run "key_rotates_and_is_named_from_the_inputs" {
  command = apply

  variables {
    name_suffix = "app"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation && output.key_rotation_enabled
    error_message = "Rotation must always be on."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/ordering-integration-app"
    error_message = "The alias must be built from name, environment and name_suffix."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "The deletion window defaults to 30 days."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "ordering-integration-app" && aws_kms_key.this.tags["Environment"] == "integration"
    error_message = "Tags from the tags input and the Name tag must be applied."
  }
}

run "root_delegates_to_iam_by_default" {
  command = apply

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:root" && jsondecode(aws_kms_key.this.policy).Statement[0].Action == ["kms:*"]
    error_message = "The account root must enable IAM policies."
  }

  assert {
    condition     = length(jsondecode(aws_kms_key.this.policy).Statement) == 1
    error_message = "Without principals or grants only the root statement exists."
  }
}

run "without_delegation_the_root_only_administers" {
  command = apply

  variables {
    enable_iam_policy_delegation = false
    encrypt_principals           = ["arn:aws:iam::123456789012:role/example-writer"]
    decrypt_principals           = ["arn:aws:iam::123456789012:role/example-reader"]
    management_principals        = ["arn:aws:iam::123456789012:role/example-admin"]
  }

  assert {
    condition     = !contains(flatten([jsondecode(aws_kms_key.this.policy).Statement[0].Action]), "kms:Decrypt") && !contains(flatten([jsondecode(aws_kms_key.this.policy).Statement[0].Action]), "kms:Encrypt")
    error_message = "The root must not be able to use the key when delegation is off."
  }

  assert {
    condition     = [for s in jsondecode(aws_kms_key.this.policy).Statement : s.Action if s.Sid == "DecryptPrincipals"][0] == ["kms:Decrypt", "kms:DescribeKey"]
    error_message = "Decrypt principals may only decrypt."
  }

  assert {
    condition     = !contains([for s in jsondecode(aws_kms_key.this.policy).Statement : s if s.Sid == "ManagementPrincipals"][0].Action, "kms:Decrypt")
    error_message = "Management principals must not be able to use the key."
  }
}

run "service_grants_can_be_narrowed_with_a_condition" {
  command = apply

  variables {
    service_grants = [{
      sid     = "CloudWatchLogsEncryption"
      service = "logs.eu-west-1.amazonaws.com"
      condition = {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/ordering-integration"]
      }
    }]
  }

  assert {
    condition     = [for s in jsondecode(aws_kms_key.this.policy).Statement : s if s.Sid == "CloudWatchLogsEncryption"][0].Principal.Service == "logs.eu-west-1.amazonaws.com"
    error_message = "The service principal must be set."
  }

  assert {
    condition     = [for s in jsondecode(aws_kms_key.this.policy).Statement : s if s.Sid == "CloudWatchLogsEncryption"][0].Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == ["arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/ordering-integration"]
    error_message = "The condition must narrow the grant to one log group."
  }
}

run "additional_statements_are_appended" {
  command = apply

  variables {
    additional_statements = [{
      Sid       = "Extra"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::123456789012:role/example" }
      Action    = ["kms:Decrypt"]
      Resource  = "*"
    }]
  }

  assert {
    condition     = length([for s in jsondecode(aws_kms_key.this.policy).Statement : s if s.Sid == "Extra"]) == 1
    error_message = "Additional statements must reach the key policy."
  }
}

run "deletion_window_is_bounded" {
  command = plan

  variables {
    deletion_window_in_days = 3
  }

  expect_failures = [var.deletion_window_in_days]
}
