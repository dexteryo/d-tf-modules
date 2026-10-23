output "alb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix for CloudWatch dimensions"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 zone id of the load balancer, for alias records"
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "Security group of the load balancer; reference it from the security group of the service"
  value       = module.security_group.security_group_id
}

output "listener_arns" {
  description = "Listener ARNs keyed like the listeners input"
  value       = { for key, listener in aws_lb_listener.this : key => listener.arn }
}

output "ingress_rules" {
  description = "Ingress rules of the load balancer security group"
  value       = module.security_group.ingress_rules
}

output "egress_rules" {
  description = "Egress rules of the load balancer security group"
  value       = module.security_group.egress_rules
}

output "load_balancer" {
  description = "Settings of the load balancer as created, for review and for tests in the calling configuration"
  value = {
    internal                   = aws_lb.this.internal
    idle_timeout               = aws_lb.this.idle_timeout
    drop_invalid_header_fields = aws_lb.this.drop_invalid_header_fields
    deletion_protection        = aws_lb.this.enable_deletion_protection
    access_logs_enabled        = anytrue([for logs in aws_lb.this.access_logs : logs.enabled])
    access_logs_bucket         = one([for logs in aws_lb.this.access_logs : logs.bucket])
  }
}

output "listeners" {
  description = "Port, protocol, TLS policy and default action of every listener, keyed like the listeners input"
  value = {
    for key, listener in aws_lb_listener.this : key => {
      port                = listener.port
      protocol            = listener.protocol
      ssl_policy          = listener.ssl_policy
      default_action_type = listener.default_action[0].type
      default_status_code = one([for response in listener.default_action[0].fixed_response : response.status_code])
    }
  }
}

output "header_forward_rules" {
  description = "Header name and value each rule matches, keyed like the header_forward_rules input"
  sensitive   = true
  value = {
    for key, rule in aws_lb_listener_rule.header_forward : key => {
      header_name  = one([for condition in rule.condition : one([for header in condition.http_header : header.http_header_name])])
      header_value = one([for condition in rule.condition : one([for header in condition.http_header : one(header.values)])])
    }
  }
}
