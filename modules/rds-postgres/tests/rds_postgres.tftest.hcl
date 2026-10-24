mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/example"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:example-AbCdEf"
    }
  }

  mock_resource "aws_db_proxy_default_target_group" {
    defaults = {
      name = "default"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds-master-AbCdEf"
        kms_key_id    = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
        secret_status = "active"
      }]
    }
  }
}

variables {
  name               = "ordering"
  environment        = "integration"
  subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222", "subnet-cccc3333"]
  security_group_ids = ["sg-0123456789abcdef0"]
  data_kms_key_arn   = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  logs_kms_key_arn   = "arn:aws:kms:eu-west-1:123456789012:key/66666666-7777-8888-9999-000000000000"
  tags               = { Environment = "integration" }
}

run "instance_is_named_encrypted_private_and_tls_only" {
  command = apply

  assert {
    condition     = aws_db_instance.this.identifier == "ordering-integration-postgres" && aws_db_instance.this.tags["Environment"] == "integration"
    error_message = "The instance is named from name and environment and carries the tags input."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted && aws_db_instance.this.kms_key_id == var.data_kms_key_arn && !aws_db_instance.this.publicly_accessible
    error_message = "Storage must be encrypted with the data key and the instance must not be public."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.master_user_secret_kms_key_id == var.data_kms_key_arn
    error_message = "RDS manages the administrator password and encrypts its secret with the data key."
  }

  assert {
    condition     = aws_db_instance.this.vpc_security_group_ids == toset(var.security_group_ids)
    error_message = "The instance uses the security groups it is given."
  }

  assert {
    condition     = alltrue([for p in aws_db_parameter_group.this.parameter : p.value == (p.name == "rds.force_ssl" ? "1" : "TLSv1.2")]) && aws_db_parameter_group.this.family == "postgres17"
    error_message = "TLS must be forced with TLS 1.2 as the minimum, on the family of the engine version."
  }
}

run "safe_defaults_for_backups_and_deletion" {
  command = apply

  assert {
    condition     = aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.final_snapshot_identifier == "ordering-integration-postgres-final"
    error_message = "Deletion protection and a final snapshot are on by default."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 7 && !aws_db_instance.this.multi_az
    error_message = "Backups default to 7 days on a single-AZ instance."
  }

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled && aws_db_instance.this.performance_insights_enabled && aws_db_instance.this.performance_insights_kms_key_id == var.data_kms_key_arn
    error_message = "IAM authentication and encrypted Performance Insights are on."
  }
}

run "settings_can_be_overridden" {
  command = apply

  variables {
    backup_retention_days = 35
    multi_az              = true
    deletion_protection   = false
    skip_final_snapshot   = true
    master_username       = "finn_admin"
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 35 && aws_db_instance.this.multi_az && !aws_db_instance.this.deletion_protection && aws_db_instance.this.username == "finn_admin"
    error_message = "Retention, Multi-AZ, deletion protection and the administrator name come from the inputs."
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == null
    error_message = "No final snapshot name when the snapshot is skipped."
  }
}

run "logs_are_exported_into_encrypted_groups" {
  command = apply

  assert {
    condition     = aws_db_instance.this.enabled_cloudwatch_logs_exports == toset(["postgresql", "upgrade"])
    error_message = "PostgreSQL and upgrade logs are exported."
  }

  assert {
    condition     = alltrue([for g in aws_cloudwatch_log_group.postgresql : g.kms_key_id == var.logs_kms_key_arn && g.retention_in_days == 365]) && aws_cloudwatch_log_group.postgresql["postgresql"].name == "/aws/rds/instance/ordering-integration-postgres/postgresql"
    error_message = "Log groups use the logs key, are named as RDS expects and are kept for a year."
  }
}

run "free_storage_alarm_notifies_the_given_topics" {
  command = apply

  variables {
    alarm_topic_arns = ["arn:aws:sns:eu-west-1:123456789012:alarms"]
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.free_storage.threshold == 5368709120 && aws_cloudwatch_metric_alarm.free_storage.treat_missing_data == "breaching"
    error_message = "The alarm fires below 5 GiB and treats missing data as a breach."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.free_storage.alarm_actions == toset(var.alarm_topic_arns) && aws_cloudwatch_metric_alarm.free_storage.ok_actions == toset(var.alarm_topic_arns)
    error_message = "Both transitions notify the topics."
  }
}

run "no_roles_and_no_proxy_by_default" {
  command = apply

  assert {
    condition     = length(aws_secretsmanager_secret.role) == 0 && length(aws_db_proxy.this) == 0 && output.proxy_endpoint == null
    error_message = "Roles and the proxy are opt-in."
  }
}

run "each_role_gets_a_generated_password_in_its_own_secret" {
  command = apply

  variables {
    database_roles = {
      app_api = { database = "app" }
      sso     = { database = "sso" }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.role) == 2 && aws_secretsmanager_secret.role["app_api"].name == "ordering-integration/db/app_api" && aws_secretsmanager_secret.role["sso"].kms_key_id == var.data_kms_key_arn
    error_message = "One secret per role, named from the inputs and encrypted with the data key."
  }

  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.role["sso"].secret_string).username == "sso" && jsondecode(aws_secretsmanager_secret_version.role["sso"].secret_string).dbname == "sso" && jsondecode(aws_secretsmanager_secret_version.role["sso"].secret_string).port == 5432
    error_message = "The secret holds the role name, its database and the port."
  }

  assert {
    condition     = random_password.role["app_api"].length == 40 && !random_password.role["app_api"].special
    error_message = "Passwords are 40 characters without special characters, so they are safe in connection strings."
  }

  assert {
    condition     = length(output.role_secret_arns) == 2
    error_message = "The output lists every role secret."
  }
}

run "proxy_signs_in_as_the_chosen_roles_only" {
  command = apply

  variables {
    database_roles = {
      app_api = { database = "app" }
      sso     = { database = "sso" }
    }

    proxy = {
      role_names         = ["app_api"]
      security_group_ids = ["sg-0fedcba9876543210"]
    }
  }

  assert {
    condition     = aws_db_proxy.this[0].require_tls && aws_db_proxy.this[0].engine_family == "POSTGRESQL" && aws_db_proxy.this[0].idle_client_timeout == 1800
    error_message = "The proxy requires TLS and defaults to a 30 minute idle timeout."
  }

  assert {
    condition     = length(aws_db_proxy.this[0].auth) == 1 && one(aws_db_proxy.this[0].auth).iam_auth == "DISABLED" && one(aws_db_proxy.this[0].auth).client_password_auth_type == "POSTGRES_SCRAM_SHA_256"
    error_message = "Only the chosen role is registered, with SCRAM and secrets."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.proxy[0].policy).Statement[0].Resource) == 1
    error_message = "The proxy role may read only the secrets of the chosen roles."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.proxy[0].policy).Statement[1].Condition.StringEquals["kms:ViaService"] == "secretsmanager.eu-west-1.amazonaws.com"
    error_message = "The proxy may use the data key only through Secrets Manager."
  }

  assert {
    condition     = aws_db_proxy_target.this[0].db_instance_identifier == "ordering-integration-postgres"
    error_message = "The proxy targets the instance."
  }
}

run "proxy_roles_must_exist" {
  command = plan

  variables {
    database_roles = {
      app_api = { database = "app" }
    }

    proxy = {
      role_names         = ["missing"]
      security_group_ids = ["sg-0fedcba9876543210"]
    }
  }

  expect_failures = [aws_db_proxy.this]
}

run "one_subnet_is_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaaa1111"]
  }

  expect_failures = [var.subnet_ids]
}

run "backup_retention_beyond_35_days_is_rejected" {
  command = plan

  variables {
    backup_retention_days = 36
  }

  expect_failures = [var.backup_retention_days]
}

run "proxy_without_roles_is_rejected" {
  command = plan

  variables {
    proxy = {
      role_names         = []
      security_group_ids = ["sg-0fedcba9876543210"]
    }
  }

  expect_failures = [var.proxy]
}

run "instance_without_security_groups_is_rejected" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}
