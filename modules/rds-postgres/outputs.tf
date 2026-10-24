output "db_identifier" {
  description = "Instance identifier, <name>-<environment>-postgres; the point-in-time restore runbook names it"
  value       = aws_db_instance.this.identifier
}

output "db_arn" {
  description = "Instance ARN"
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "Instance address, for clients that connect without the proxy"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.this.port
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint, or null when there is no proxy"
  value       = one(aws_db_proxy.this[*].endpoint)
}

output "master_user_secret_arn" {
  description = "Secret that RDS manages for the administrator account"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "role_secret_arns" {
  description = "Secrets Manager secret of each database role, keyed by role name"
  value       = { for role, secret in aws_secretsmanager_secret.role : role => secret.arn }
}
