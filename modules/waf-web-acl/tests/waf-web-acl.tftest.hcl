mock_provider "aws" {
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/example-integration/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-example-integration"
    }
  }
}

variables {
  name        = "example"
  environment = "integration"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  tags        = { Environment = "integration" }
}

run "web_acl_is_named_tagged_and_scoped_to_cloudfront" {
  command = apply

  assert {
    condition     = aws_wafv2_web_acl.this.name == "example-integration" && aws_wafv2_web_acl.this.tags["Name"] == "example-integration" && aws_wafv2_web_acl.this.tags["Environment"] == "integration"
    error_message = "The web ACL is named from name and environment and carries the tags input."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT"
    error_message = "The web ACL must use the CLOUDFRONT scope."
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action[0].allow) == 1 && length(aws_wafv2_web_acl.this.default_action[0].block) == 0
    error_message = "Requests no rule matches are allowed."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.visibility_config[0].cloudwatch_metrics_enabled && aws_wafv2_web_acl.this.visibility_config[0].sampled_requests_enabled && aws_wafv2_web_acl.this.visibility_config[0].metric_name == "example-integration"
    error_message = "The web ACL publishes metrics and samples requests under its full name."
  }
}

run "name_suffix_extends_the_name" {
  command = plan

  variables {
    name_suffix = "edge"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.name == "example-integration-edge" && aws_cloudwatch_log_group.waf.name == "aws-waf-logs-example-integration-edge"
    error_message = "A suffix is the last part of the name."
  }
}

run "empty_environment_is_left_out_of_the_name" {
  command = plan

  variables {
    environment = ""
  }

  assert {
    condition     = aws_wafv2_web_acl.this.name == "example"
    error_message = "An empty environment must not leave a dangling hyphen."
  }
}

run "default_rule_groups_are_the_four_aws_groups_with_fixed_priorities" {
  command = plan

  assert {
    condition = toset([for r in aws_wafv2_web_acl.this.rule : r.name if r.name != "rate-limit-per-ip"]) == toset([
      "AWSManagedRulesAmazonIpReputationList",
      "AWSManagedRulesAnonymousIpList",
      "AWSManagedRulesKnownBadInputsRuleSet",
      "AWSManagedRulesCommonRuleSet",
    ])
    error_message = "The default groups are IP reputation, anonymous IP, known bad inputs and the common rule set."
  }

  assert {
    condition     = toset([for r in aws_wafv2_web_acl.this.rule : r.priority if r.name != "rate-limit-per-ip"]) == toset([10, 15, 20, 30])
    error_message = "The default priorities are 10, 15, 20 and 30."
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.name == "rate-limit-per-ip" || (r.statement[0].managed_rule_group_statement[0].vendor_name == "AWS" && length(r.override_action[0].none) == 1)])
    error_message = "Managed groups use the vendor AWS and keep their own actions."
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.visibility_config[0].cloudwatch_metrics_enabled && r.visibility_config[0].sampled_requests_enabled])
    error_message = "Every rule publishes metrics and samples requests."
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.visibility_config[0].metric_name if r.priority == 10] == ["example-integration-AWSManagedRulesAmazonIpReputationList"]
    error_message = "Rule metrics are prefixed with the full name."
  }
}

run "rate_rule_blocks_per_ip_after_the_last_group" {
  command = plan

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.priority if r.name == "rate-limit-per-ip"] == [40]
    error_message = "With the default groups the rate rule priority is 40, the highest group priority plus 10."
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].limit if r.name == "rate-limit-per-ip"] == [1000]
    error_message = "The default limit is 1000 requests per 5 minutes."
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].aggregate_key_type if r.name == "rate-limit-per-ip"] == ["IP"]
    error_message = "The rate rule counts per source IP."
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : length(r.action[0].block) if r.name == "rate-limit-per-ip"] == [1]
    error_message = "The rate rule blocks."
  }
}

run "rate_rule_priority_follows_the_highest_group_priority" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", priority = 5 },
      { name = "AWSManagedRulesSQLiRuleSet", priority = 100 },
    ]
    rate_limit_per_5_minutes = 250
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.priority if r.name == "rate-limit-per-ip"] == [110]
    error_message = "The rate rule priority is max(priorities) + 10."
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].limit if r.name == "rate-limit-per-ip"] == [250]
    error_message = "The limit input is used as given."
  }
}

run "rate_rule_priority_is_ten_without_managed_groups" {
  command = plan

  variables {
    managed_rule_groups = []
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.priority] == [10]
    error_message = "With no managed groups the rate rule is the only rule, at priority 10."
  }
}

run "null_rate_limit_turns_the_rate_rule_off" {
  command = plan

  variables {
    rate_limit_per_5_minutes = null
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 4 && !contains([for r in aws_wafv2_web_acl.this.rule : r.name], "rate-limit-per-ip")
    error_message = "A null rate limit leaves only the managed groups."
  }
}

run "vendor_name_can_be_overridden" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "ExampleRuleGroup", priority = 1, vendor_name = "ExampleVendor" },
    ]
  }

  assert {
    condition     = [for r in aws_wafv2_web_acl.this.rule : r.statement[0].managed_rule_group_statement[0].vendor_name if r.name == "ExampleRuleGroup"] == ["ExampleVendor"]
    error_message = "A rule group from another vendor keeps its vendor name."
  }
}

run "log_group_is_named_encrypted_and_kept_for_seven_days" {
  command = apply

  assert {
    condition     = aws_cloudwatch_log_group.waf.name == "aws-waf-logs-example-integration"
    error_message = "WAF only delivers to log groups whose name starts with aws-waf-logs-."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.waf.retention_in_days == 7
    error_message = "The log group uses the given key and keeps logs for 7 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.tags["Environment"] == "integration"
    error_message = "The log group carries the tags input."
  }
}

run "retention_can_be_changed" {
  command = plan

  variables {
    log_retention_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.retention_in_days == 30
    error_message = "log_retention_days sets the retention."
  }
}

run "logging_redacts_headers_path_and_query_by_default" {
  command = apply

  assert {
    condition     = one(aws_wafv2_web_acl_logging_configuration.this.log_destination_configs) == aws_cloudwatch_log_group.waf.arn
    error_message = "Logs go to the module's log group."
  }

  assert {
    condition     = [for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f.single_header[0].name if length(f.single_header) > 0] == ["authorization", "cookie"]
    error_message = "The authorization and cookie headers are redacted."
  }

  assert {
    condition     = length([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f if length(f.uri_path) > 0]) == 1
    error_message = "The URI path is redacted."
  }

  assert {
    condition     = length([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f if length(f.query_string) > 0]) == 1
    error_message = "The query string is redacted."
  }
}

run "redactions_can_be_switched_off" {
  command = plan

  variables {
    redacted_headers    = []
    redact_uri_path     = false
    redact_query_string = false
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this.redacted_fields) == 0
    error_message = "With every redaction off no field is redacted."
  }
}

run "custom_redacted_headers_replace_the_default" {
  command = plan

  variables {
    redacted_headers    = ["x-api-key"]
    redact_uri_path     = false
    redact_query_string = false
  }

  assert {
    condition     = [for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f.single_header[0].name] == ["x-api-key"]
    error_message = "redacted_headers replaces the default list."
  }
}

run "outputs_expose_the_web_acl_and_log_group" {
  command = apply

  assert {
    condition     = output.web_acl_arn == aws_wafv2_web_acl.this.arn && output.web_acl_id == aws_wafv2_web_acl.this.id && output.log_group_arn == aws_cloudwatch_log_group.waf.arn
    error_message = "Outputs must point at the web ACL and the log group."
  }
}

run "duplicate_group_names_are_rejected" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", priority = 1 },
      { name = "AWSManagedRulesCommonRuleSet", priority = 2 },
    ]
  }

  expect_failures = [var.managed_rule_groups]
}

run "duplicate_priorities_are_rejected" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", priority = 1 },
      { name = "AWSManagedRulesSQLiRuleSet", priority = 1 },
    ]
  }

  expect_failures = [var.managed_rule_groups]
}

run "rate_limit_below_ten_is_rejected" {
  command = plan

  variables {
    rate_limit_per_5_minutes = 9
  }

  expect_failures = [var.rate_limit_per_5_minutes]
}
