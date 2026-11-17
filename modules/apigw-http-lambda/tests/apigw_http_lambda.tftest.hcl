mock_provider "aws" {
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "abc123"
      execution_arn = "arn:aws:execute-api:eu-west-1:123456789012:abc123"
    }
  }

  mock_resource "aws_apigatewayv2_domain_name" {
    defaults = {
      domain_name_configuration = {
        target_domain_name = "d-abc123.execute-api.eu-west-1.amazonaws.com"
        hosted_zone_id     = "Z2HOSTEDZONE"
      }
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/ordering-integration-webhooks/api/access"
    }
  }
}

variables {
  name                = "ordering"
  environment         = "integration"
  name_suffix         = "webhooks"
  tags                = { Environment = "integration" }
  function_name       = "ordering-integration-intake"
  function_invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:ordering-integration-intake/invocations"
  routes              = ["POST /webhooks/acme", "POST /webhooks/globex"]
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:123456789012:key/11111111-1111-1111-1111-111111111111"
}

run "one_route_per_key_all_to_the_function" {
  command = apply

  assert {
    condition     = toset([for route in aws_apigatewayv2_route.this : route.route_key]) == toset(["POST /webhooks/acme", "POST /webhooks/globex"])
    error_message = "Each given route key becomes one route."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this.integration_uri == var.function_invoke_arn && aws_apigatewayv2_integration.this.payload_format_version == "2.0"
    error_message = "Every route proxies to the function with the version 2.0 payload."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.name == "ordering-integration-webhooks" && aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "The API is an HTTP API named <name>-<environment>-<name_suffix>."
  }
}

run "each_route_has_its_own_invoke_permission" {
  command = apply

  assert {
    condition     = aws_lambda_permission.this["POST /webhooks/acme"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:abc123/*/POST/webhooks/acme"
    error_message = "The permission names the method and path, not a wildcard route."
  }

  assert {
    condition     = alltrue([for permission in aws_lambda_permission.this : permission.principal == "apigateway.amazonaws.com" && permission.function_name == var.function_name])
    error_message = "Only API Gateway may invoke the function, and only the named one."
  }

  assert {
    condition     = length(toset([for permission in aws_lambda_permission.this : permission.statement_id])) == 2 && alltrue([for permission in aws_lambda_permission.this : can(regex("^[A-Za-z0-9_-]{1,100}$", permission.statement_id))])
    error_message = "Statement ids are unique and use only characters Lambda accepts."
  }
}

run "the_stage_throttles_and_logs_to_an_encrypted_group" {
  command = apply

  variables {
    throttling_rate_limit  = 10
    throttling_burst_limit = 20
  }

  assert {
    condition     = one(aws_apigatewayv2_stage.default.default_route_settings).throttling_rate_limit == 10 && one(aws_apigatewayv2_stage.default.default_route_settings).throttling_burst_limit == 20
    error_message = "The stage limits follow the inputs."
  }

  assert {
    condition     = length(aws_apigatewayv2_stage.default.route_settings) == 2 && alltrue([for settings in aws_apigatewayv2_stage.default.route_settings : settings.throttling_rate_limit == 10])
    error_message = "Every route carries the limits too."
  }

  assert {
    condition     = aws_cloudwatch_log_group.access.kms_key_id == var.logs_kms_key_arn && aws_cloudwatch_log_group.access.retention_in_days == 365
    error_message = "Access logs are encrypted with the given key and kept for a year by default."
  }

  assert {
    condition     = !strcontains(one(aws_apigatewayv2_stage.default.access_log_settings).format, "requestBody") && !strcontains(one(aws_apigatewayv2_stage.default.access_log_settings).format, "header")
    error_message = "The access log never records request bodies or headers."
  }
}

run "a_named_path_parameter_gets_a_permission_for_any_value_of_that_segment" {
  command = apply

  variables {
    routes = ["POST /webhooks/acme/{token}"]
  }

  assert {
    condition     = aws_apigatewayv2_route.this["POST /webhooks/acme/{token}"].route_key == "POST /webhooks/acme/{token}"
    error_message = "The route keeps its path parameter."
  }

  assert {
    condition     = aws_lambda_permission.this["POST /webhooks/acme/{token}"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:abc123/*/POST/webhooks/acme/*"
    error_message = "The permission matches one segment of any value where the parameter is, and nothing else."
  }

  assert {
    condition     = can(regex("^[A-Za-z0-9_-]{1,100}$", aws_lambda_permission.this["POST /webhooks/acme/{token}"].statement_id))
    error_message = "The statement id of a parameter route uses only characters Lambda accepts."
  }
}

run "greedy_parameters_are_refused" {
  command = plan

  variables {
    routes = ["POST /webhooks/{proxy+}"]
  }

  expect_failures = [var.routes]
}

run "a_parameter_must_be_a_whole_segment" {
  command = plan

  variables {
    routes = ["POST /webhooks/acme-{token}"]
  }

  expect_failures = [var.routes]
}

run "the_default_route_is_refused" {
  command = plan

  variables {
    routes = ["$default"]
  }

  expect_failures = [var.routes]
}

run "no_custom_domain_unless_asked" {
  command = apply

  assert {
    condition     = length(aws_apigatewayv2_domain_name.this) == 0 && length(aws_apigatewayv2_api_mapping.this) == 0
    error_message = "Without custom_domain the module creates no domain and no mapping."
  }

  assert {
    condition     = output.custom_domain_url == null && output.custom_domain_target == null
    error_message = "The custom domain outputs are null when there is no custom domain."
  }
}

run "a_custom_domain_serves_the_default_stage_over_tls_1_2" {
  command = apply

  variables {
    custom_domain = {
      domain_name     = "hooks.example.com"
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = one(aws_apigatewayv2_domain_name.this).domain_name == "hooks.example.com"
    error_message = "The domain uses the given name."
  }

  assert {
    condition = alltrue([
      for config in one(aws_apigatewayv2_domain_name.this).domain_name_configuration :
      config.endpoint_type == "REGIONAL" && config.security_policy == "TLS_1_2" && config.certificate_arn == var.custom_domain.certificate_arn
    ])
    error_message = "The domain is regional, uses the given certificate and refuses TLS older than 1.2."
  }

  assert {
    condition     = one(aws_apigatewayv2_api_mapping.this).stage == "$default" && one(aws_apigatewayv2_api_mapping.this).api_id == "abc123" && one(aws_apigatewayv2_api_mapping.this).api_mapping_key == null
    error_message = "The domain root maps to the API's default stage."
  }

  assert {
    condition     = output.custom_domain_url == "https://hooks.example.com"
    error_message = "custom_domain_url is the https URL of the domain."
  }

  assert {
    condition     = output.custom_domain_target.domain_name == "d-abc123.execute-api.eu-west-1.amazonaws.com" && output.custom_domain_target.hosted_zone_id == "Z2HOSTEDZONE"
    error_message = "custom_domain_target gives the alias target for a DNS record."
  }
}

run "a_custom_domain_name_is_validated" {
  command = plan

  variables {
    custom_domain = {
      domain_name     = "Hooks.Example.com."
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-2222-2222-222222222222"
    }
  }

  expect_failures = [var.custom_domain]
}

run "routes_need_a_method_and_must_not_be_empty" {
  command = plan

  variables {
    routes = []
  }

  expect_failures = [var.routes]
}

run "the_integration_timeout_is_validated" {
  command = plan

  variables {
    integration_timeout_ms = 60000
  }

  expect_failures = [var.integration_timeout_ms]
}
