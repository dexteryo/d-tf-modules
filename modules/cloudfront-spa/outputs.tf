output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN, for cloudfront_distribution_arn of modules/s3-bucket and the aws:SourceArn condition of the key policy"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name to point the DNS aliases at"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route 53 hosted zone ID of CloudFront, for alias records"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "origin_access_control_id" {
  description = "ID of the origin access control that signs requests to the S3 bucket"
  value       = aws_cloudfront_origin_access_control.this.id
}
