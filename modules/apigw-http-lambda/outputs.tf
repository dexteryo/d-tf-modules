output "invoke_url" {
  description = "Base URL of the API; append a route path"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  description = "ID of the HTTP API"
  value       = aws_apigatewayv2_api.this.id
}

output "execution_arn" {
  description = "Execution ARN of the HTTP API, for further invoke permissions"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "access_log_group_name" {
  description = "Name of the access log group"
  value       = aws_cloudwatch_log_group.access.name
}

output "custom_domain_url" {
  description = "https URL of the custom domain, or null without one; append a route path"
  value       = var.custom_domain == null ? null : "https://${var.custom_domain.domain_name}"
}

output "custom_domain_target" {
  description = "Alias target for the custom domain's DNS record (domain_name and hosted_zone_id), or null without one"
  value = var.custom_domain == null ? null : {
    domain_name    = one(aws_apigatewayv2_domain_name.this[0].domain_name_configuration).target_domain_name
    hosted_zone_id = one(aws_apigatewayv2_domain_name.this[0].domain_name_configuration).hosted_zone_id
  }
}
