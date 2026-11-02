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
