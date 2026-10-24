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
  name_suffix = "documents"
  kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  tags        = { Environment = "integration" }
}

run "name_is_built_from_the_inputs_and_the_account" {
  command = apply

  assert {
    condition     = aws_s3_bucket.this.bucket == "ordering-integration-documents-123456789012"
    error_message = "The bucket name must be name, environment, suffix and account ID."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "ordering-integration-documents-123456789012" && aws_s3_bucket.this.tags["Environment"] == "integration"
    error_message = "Tags from the tags input and the Name tag must be applied."
  }
}

run "account_id_can_be_left_out" {
  command = apply

  variables {
    append_account_id = false
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "ordering-integration-documents"
    error_message = "Without append_account_id the name ends at the suffix."
  }
}

run "bucket_is_private_encrypted_and_versioned" {
  command = apply

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "All four Block Public Access settings must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "Objects must be encrypted with KMS."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn
    error_message = "Objects must use the key that was passed in."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be on."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled."
  }
}

run "plain_policy_only_denies_insecure_transport" {
  command = apply

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1 && jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport"
    error_message = "Without CloudFront the policy has only the TLS statement."
  }
}

run "object_lock_is_off_by_default_and_old_versions_expire" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_object_lock_configuration.this) == 0 && !aws_s3_bucket.this.object_lock_enabled
    error_message = "Object Lock must be off unless a retention is given."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration).noncurrent_days == 90
    error_message = "Superseded versions expire after 90 days by default."
  }
}

run "object_lock_uses_compliance_mode_and_keeps_versions" {
  command = apply

  variables {
    object_lock_retention_days = 3
  }

  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled
    error_message = "The bucket must be created with Object Lock."
  }

  assert {
    condition     = one(aws_s3_bucket_object_lock_configuration.this).rule[0].default_retention[0].mode == "COMPLIANCE" && one(aws_s3_bucket_object_lock_configuration.this).rule[0].default_retention[0].days == 3
    error_message = "Retention must be compliance mode for the given days."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration) == 0
    error_message = "Locked versions cannot expire, so no expiration rule may be set."
  }
}

run "cloudfront_gets_read_access_through_origin_access_control" {
  command = apply

  variables {
    cloudfront_distribution_arn = "arn:aws:cloudfront::123456789012:distribution/EXAMPLE"
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2
    error_message = "A distribution adds one statement."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Principal.Service == "cloudfront.amazonaws.com" && jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Action == "s3:GetObject" && jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::123456789012:distribution/EXAMPLE"
    error_message = "CloudFront may only read objects, and only from that distribution."
  }
}

run "zero_day_retention_is_rejected" {
  command = plan

  variables {
    object_lock_retention_days = 0
  }

  expect_failures = [var.object_lock_retention_days]
}

run "empty_name_is_rejected" {
  command = plan

  variables {
    name = " "
  }

  expect_failures = [var.name]
}

run "zero_day_lifecycle_settings_are_rejected" {
  command = plan

  variables {
    noncurrent_version_expiration_days     = 0
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days, var.abort_incomplete_multipart_upload_days]
}
