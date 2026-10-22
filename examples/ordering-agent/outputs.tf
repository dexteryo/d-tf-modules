output "service_name" {
  description = "ECS service name for the deploy workflow"
  value       = module.ordering_agent.service_name
}

output "cluster_name" {
  description = "ECS cluster name for the deploy workflow"
  value       = module.cluster.cluster_name
}

output "task_definition_family" {
  description = "Task definition family for the deploy workflow"
  value       = module.ordering_agent.task_definition_family
}

output "sessions_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.sessions.name
}
