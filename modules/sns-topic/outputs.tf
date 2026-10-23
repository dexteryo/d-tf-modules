output "topic_arn" {
  description = "ARN of the topic; pass it as alarm_actions to the ecs-service-alarms module"
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "Name of the topic"
  value       = aws_sns_topic.this.name
}
