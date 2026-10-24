locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))

  validation_names = toset([for name in concat([var.domain_name], var.subject_alternative_names) : trimprefix(name, "*.")])

  validation_records = {
    for validation_name in local.validation_names : validation_name => [
      for option in aws_acm_certificate.this.domain_validation_options : {
        name   = option.resource_record_name
        type   = option.resource_record_type
        record = option.resource_record_value
      }
      if trimprefix(option.domain_name, "*.") == validation_name
    ][0]
  }
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  key_algorithm             = var.key_algorithm
  tags                      = merge(var.tags, { Name = local.full_name })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = !contains(var.subject_alternative_names, var.domain_name)
      error_message = "subject_alternative_names must not repeat domain_name."
    }
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_records

  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}
