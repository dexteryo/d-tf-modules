output "schedule_group_name" {
  description = "Name of the schedule group. The operator workflow reads the targets of its schedules"
  value       = aws_scheduler_schedule_group.this.name
}

output "scheduler_role_arn" {
  description = "ARN of the role EventBridge Scheduler uses to reach the targets"
  value       = aws_iam_role.scheduler.arn
}

output "operator_role_arn" {
  description = "ARN of the GitHub OIDC operator role, or null when operator is not set"
  value       = one(aws_iam_role.operator[*].arn)
}
