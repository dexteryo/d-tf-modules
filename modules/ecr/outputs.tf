output "repository_url" {
  description = "URL of the repository, <registry>/<name>"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository including the namespace"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "Account id of the registry"
  value       = aws_ecr_repository.this.registry_id
}

output "kms_key_arn" {
  description = "Key that encrypts the images, given or created"
  value       = local.kms_key_arn
}
