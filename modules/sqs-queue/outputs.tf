output "queue_arn" {
  description = "ARN of the queue; grant producers sqs:SendMessage and consumers the receive actions on it"
  value       = aws_sqs_queue.this.arn
}

output "queue_url" {
  description = "URL of the queue"
  value       = aws_sqs_queue.this.url
}

output "queue_name" {
  description = "Name of the queue"
  value       = aws_sqs_queue.this.name
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_name" {
  description = "Name of the dead-letter queue"
  value       = aws_sqs_queue.dlq.name
}

output "dlq_alarm_arn" {
  description = "ARN of the alarm that fires while the dead-letter queue holds a message"
  value       = aws_cloudwatch_metric_alarm.dlq_not_empty.arn
}
