output "instance_id" {
  description = "Target of aws ssm start-session"
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "Security group of the instance; it has no ingress rule"
  value       = aws_security_group.this.id
}

output "role_name" {
  description = "Instance role, for attaching extra policies such as session logging"
  value       = aws_iam_role.this.name
}

output "proxy_port" {
  description = "Port squid listens on, on the instance's loopback"
  value       = var.proxy_port
}

output "port_forward_command" {
  description = "AWS CLI command that opens the proxy on localhost:<proxy_port>"
  value       = "aws ssm start-session --target ${aws_instance.this.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=${var.proxy_port},localPortNumber=${var.proxy_port}"
}
