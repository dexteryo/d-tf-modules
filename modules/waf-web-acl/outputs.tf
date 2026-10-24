output "web_acl_arn" {
  description = "ARN of the CloudFront web ACL, for the web_acl_arn input of modules/cloudfront-spa"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the web ACL"
  value       = aws_wafv2_web_acl.this.id
}

output "log_group_arn" {
  description = "Log group that receives the WAF logs"
  value       = aws_cloudwatch_log_group.waf.arn
}
