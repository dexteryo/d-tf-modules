mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name = "ordering-agent"
  tags = { Environment = "integration" }
}

run "tags_are_immutable_scanned_and_encrypted_with_kms" {
  command = apply

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Tags must be immutable by default."
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "Scan on push must be on by default."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS"
    error_message = "Images must be encrypted with KMS."
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "A repository with images must not be deletable by accident."
  }
}

run "creates_its_own_key_by_default" {
  command = apply

  assert {
    condition     = length(module.kms) == 1
    error_message = "By default the module must create a key."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "The repository must use the key the module created."
  }
}

run "uses_the_given_key_and_creates_none" {
  command = apply

  variables {
    create_kms_key = false
    kms_key_arn    = "arn:aws:kms:eu-west-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = length(module.kms) == 0
    error_message = "A given key must replace the module's own key."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].kms_key == var.kms_key_arn
    error_message = "The repository must use the given key."
  }
}

run "namespace_prefixes_the_name" {
  command = apply

  variables {
    namespace = "example-org"
  }

  assert {
    condition     = aws_ecr_repository.this.name == "example-org/ordering-agent"
    error_message = "The repository name is <namespace>/<name>."
  }
}

run "lifecycle_expires_untagged_after_seven_days_and_keeps_thirty_tagged" {
  command = apply

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.countNumber == 7 && jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.tagStatus == "untagged"
    error_message = "Untagged images expire after 7 days."
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection.countNumber == 30
    error_message = "The newest 30 tagged images are kept."
  }
}

run "lifecycle_can_be_turned_off" {
  command = apply

  variables {
    enable_lifecycle_policy = false
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "enable_lifecycle_policy = false must remove the policy."
  }
}

run "no_repository_policy_by_default" {
  command = apply

  assert {
    condition     = length(aws_ecr_repository_policy.pull) == 0
    error_message = "Only this account may pull unless other accounts are listed."
  }
}

run "listed_accounts_may_pull_but_not_push" {
  command = apply

  variables {
    pull_account_ids = ["123456789012"]
  }

  assert {
    condition     = jsondecode(aws_ecr_repository_policy.pull[0].policy).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:root"]
    error_message = "The listed account must be the principal."
  }

  assert {
    condition     = alltrue([for a in jsondecode(aws_ecr_repository_policy.pull[0].policy).Statement[0].Action : !strcontains(a, "Put") && !strcontains(a, "Upload")])
    error_message = "Other accounts get pull actions only."
  }
}

run "rejects_malformed_account_ids" {
  command = plan

  variables {
    pull_account_ids = ["not-an-account"]
  }

  expect_failures = [var.pull_account_ids]
}

run "own_key_is_required_when_none_is_created" {
  command = plan

  variables {
    create_kms_key = false
  }

  expect_failures = [aws_ecr_repository.this]
}
