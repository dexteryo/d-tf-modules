mock_provider "aws" {}

variables {
  name           = "example"
  environment    = "integration"
  domain_name    = "example.com"
  hosted_zone_id = "Z0123456789ABCDEFGHIJ"
  tags           = { Environment = "integration" }
}

run "certificate_is_named_tagged_and_validated_by_dns_with_defaults" {
  command = apply

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Name"] == "example-integration" && aws_acm_certificate.this.tags["Environment"] == "integration"
    error_message = "The Name tag is built from name and environment and the tags input is kept."
  }

  assert {
    condition     = aws_acm_certificate.this.validation_method == "DNS" && aws_acm_certificate.this.key_algorithm == "RSA_2048"
    error_message = "Validation is by DNS and the key algorithm defaults to RSA_2048."
  }

  assert {
    condition     = length(aws_acm_certificate.this.subject_alternative_names) == 0
    error_message = "There are no extra names by default."
  }

  assert {
    condition     = aws_acm_certificate_validation.this.timeouts.create == "30m"
    error_message = "The validation timeout defaults to 30 minutes."
  }
}

run "name_suffix_extends_the_name_tag" {
  command = plan

  variables {
    name_suffix = "edge"
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Name"] == "example-integration-edge"
    error_message = "A suffix is the last part of the name."
  }
}

run "empty_environment_is_left_out_of_the_name_tag" {
  command = plan

  variables {
    environment = ""
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Name"] == "example"
    error_message = "An empty environment must not leave a stray dash."
  }
}

run "one_name_gives_one_validation_record" {
  command = apply

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1 && contains(keys(aws_route53_record.validation), "example.com")
    error_message = "One name needs one validation record."
  }

  assert {
    condition     = aws_route53_record.validation["example.com"].name == "_aaa.example.com." && aws_route53_record.validation["example.com"].type == "CNAME" && aws_route53_record.validation["example.com"].records == toset(["_bbb.acm-validations.aws."])
    error_message = "The record carries the name, type and value ACM asks for."
  }

  assert {
    condition     = aws_route53_record.validation["example.com"].zone_id == "Z0123456789ABCDEFGHIJ" && aws_route53_record.validation["example.com"].ttl == 60 && aws_route53_record.validation["example.com"].allow_overwrite
    error_message = "Records go in the given zone with a TTL of 60 and may overwrite."
  }
}

run "apex_and_wildcard_give_one_validation_record" {
  command   = apply
  state_key = "apex_and_wildcard"

  variables {
    subject_alternative_names = ["*.example.com"]
  }

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
        {
          domain_name           = "*.example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1
    error_message = "A name and its wildcard share one CNAME, so only one record may be created."
  }

  assert {
    condition     = length(output.validation_record_fqdns) == 1
    error_message = "The output lists the single record."
  }

  assert {
    condition     = toset(aws_acm_certificate.this.subject_alternative_names) == toset(["*.example.com"])
    error_message = "The wildcard is passed to the certificate."
  }
}

run "distinct_names_give_one_validation_record_each" {
  command   = apply
  state_key = "distinct_names"

  variables {
    subject_alternative_names = ["ops.example.com", "api.example.com"]
  }

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_aaa.acm-validations.aws."
        },
        {
          domain_name           = "ops.example.com"
          resource_record_name  = "_bbb.ops.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
        {
          domain_name           = "api.example.com"
          resource_record_name  = "_ccc.api.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_ccc.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = toset(keys(aws_route53_record.validation)) == toset(["example.com", "ops.example.com", "api.example.com"])
    error_message = "Every distinct name gets its own validation record."
  }

  assert {
    condition     = aws_route53_record.validation["ops.example.com"].name == "_bbb.ops.example.com."
    error_message = "Each record keeps the name ACM gave its own domain."
  }

  assert {
    condition     = length(output.validation_record_fqdns) == 3
    error_message = "The output lists every record."
  }
}

run "wildcard_primary_name_is_accepted" {
  command = plan

  variables {
    domain_name = "*.example.com"
  }

  assert {
    condition     = aws_acm_certificate.this.domain_name == "*.example.com"
    error_message = "A wildcard primary name is allowed."
  }
}

run "output_is_the_validated_arn" {
  command = apply

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = output.certificate_arn == aws_acm_certificate_validation.this.certificate_arn
    error_message = "certificate_arn must come from the validation resource so it waits for issuance."
  }

  assert {
    condition     = output.certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555" && output.domain_name == "example.com"
    error_message = "The outputs carry the ARN and the primary name."
  }

  assert {
    condition     = toset(aws_acm_certificate_validation.this.validation_record_fqdns) == toset(output.validation_record_fqdns)
    error_message = "The validation waits for exactly the records the output lists."
  }
}

run "key_algorithm_is_passed_through" {
  command = plan

  variables {
    key_algorithm = "EC_secp384r1"
  }

  assert {
    condition     = aws_acm_certificate.this.key_algorithm == "EC_secp384r1"
    error_message = "The key algorithm must reach the certificate."
  }
}

run "validation_timeout_is_passed_through" {
  command = apply

  variables {
    validation_timeout = "10m"
  }

  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      domain_validation_options = [
        {
          domain_name           = "example.com"
          resource_record_name  = "_aaa.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_bbb.acm-validations.aws."
        },
      ]
    }
  }

  assert {
    condition     = aws_acm_certificate_validation.this.timeouts.create == "10m"
    error_message = "The timeout must reach the validation resource."
  }
}

run "upper_case_domain_name_is_rejected" {
  command = plan

  variables {
    domain_name = "Example.com"
  }

  expect_failures = [var.domain_name]
}

run "trailing_dot_domain_name_is_rejected" {
  command = plan

  variables {
    domain_name = "example.com."
  }

  expect_failures = [var.domain_name]
}

run "wildcard_in_the_middle_is_rejected" {
  command = plan

  variables {
    domain_name = "app.*.example.com"
  }

  expect_failures = [var.domain_name]
}

run "single_label_domain_name_is_rejected" {
  command = plan

  variables {
    domain_name = "localhost"
  }

  expect_failures = [var.domain_name]
}

run "malformed_subject_alternative_name_is_rejected" {
  command = plan

  variables {
    subject_alternative_names = ["Ops.example.com"]
  }

  expect_failures = [var.subject_alternative_names]
}

run "duplicate_subject_alternative_names_are_rejected" {
  command = plan

  variables {
    subject_alternative_names = ["ops.example.com", "ops.example.com"]
  }

  expect_failures = [var.subject_alternative_names]
}

run "subject_alternative_name_equal_to_domain_name_is_rejected" {
  command = plan

  variables {
    subject_alternative_names = ["example.com"]
  }

  expect_failures = [aws_acm_certificate.this]
}

run "malformed_hosted_zone_id_is_rejected" {
  command = plan

  variables {
    hosted_zone_id = "example.com"
  }

  expect_failures = [var.hosted_zone_id]
}

run "unknown_key_algorithm_is_rejected" {
  command = plan

  variables {
    key_algorithm = "RSA_4096"
  }

  expect_failures = [var.key_algorithm]
}

run "malformed_validation_timeout_is_rejected" {
  command = plan

  variables {
    validation_timeout = "half an hour"
  }

  expect_failures = [var.validation_timeout]
}
