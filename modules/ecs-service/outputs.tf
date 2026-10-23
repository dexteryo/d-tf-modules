output "service_name" {
  description = "Name of the ECS service"
  value       = one(concat(aws_ecs_service.externally_managed[*].name, aws_ecs_service.terraform_managed[*].name))
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = one(concat(aws_ecs_service.externally_managed[*].id, aws_ecs_service.terraform_managed[*].id))
}

output "task_definition_family" {
  description = "Task definition family. Pass it to the ecs-deploy action"
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "ARN of the task definition revision Terraform last registered"
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_arn" {
  description = "ARN of the task role"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task role"
  value       = aws_iam_role.task.name
}

output "execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.execution.arn
}

output "target_group_arn" {
  description = "ARN of the target group, null without a load balancer"
  value       = one(aws_lb_target_group.this[*].arn)
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group for CloudWatch dimensions, null without a load balancer"
  value       = one(aws_lb_target_group.this[*].arn_suffix)
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "container_names" {
  description = "Names of the containers in the task"
  value       = var.containers[*].name
}
