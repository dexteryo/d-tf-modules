locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))
  routes    = { for route in var.routes : route => route }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/${local.full_name}/api/access"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

resource "aws_apigatewayv2_api" "this" {
  name          = local.full_name
  protocol_type = "HTTP"
  tags          = merge(var.tags, { Name = local.full_name })
}

resource "aws_apigatewayv2_integration" "this" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.function_invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = var.integration_timeout_ms
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_lambda_permission" "this" {
  for_each = local.routes

  statement_id  = "AllowApiGateway-${replace(each.value, "/[^A-Za-z0-9_-]/", "-")}-${substr(sha1(each.value), 0, 8)}"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/${replace(each.value, " ", "")}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags

  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }

  dynamic "route_settings" {
    for_each = aws_apigatewayv2_route.this

    content {
      route_key              = route_settings.value.route_key
      throttling_rate_limit  = var.throttling_rate_limit
      throttling_burst_limit = var.throttling_burst_limit
    }
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      requestTime             = "$context.requestTime"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationStatus       = "$context.integrationStatus"
      integrationLatency      = "$context.integrationLatency"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}
