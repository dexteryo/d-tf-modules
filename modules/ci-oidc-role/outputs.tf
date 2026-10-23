output "role_arn" {
  description = "ARN of the role; pass it as role-to-assume to the workflows of d-github-actions"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role"
  value       = aws_iam_role.this.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider the role trusts"
  value       = local.provider_arn
}

output "trust_subject" {
  description = "The sub claim the role accepts, repo:<owner>/<name>:environment:<environment>"
  value       = local.subject
}
