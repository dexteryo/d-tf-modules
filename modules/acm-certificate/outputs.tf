output "certificate_arn" {
  description = "ARN of the certificate. Only known once ACM has issued it, so a listener or distribution that uses it waits for validation"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "Primary name of the certificate"
  value       = aws_acm_certificate.this.domain_name
}

output "validation_record_fqdns" {
  description = "Names of the DNS validation records in the hosted zone. Keep them: ACM renews the certificate through them"
  value       = [for record in aws_route53_record.validation : record.fqdn]
}
