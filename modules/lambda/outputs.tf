output "function_name" {
  description = "Name of the function; the deploy workflow updates its code by this name"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the function"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN, the integration target for the apigw-http-lambda module"
  value       = aws_lambda_function.this.invoke_arn
}

output "role_arn" {
  description = "ARN of the function's execution role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the function's execution role, for attaching further policies"
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "Name of the function's log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the function's log group"
  value       = aws_cloudwatch_log_group.this.arn
}
