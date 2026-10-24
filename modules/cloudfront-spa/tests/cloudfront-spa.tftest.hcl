mock_provider "aws" {
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E1EXAMPLE12345"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/example-integration"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:example-integration"
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/example"
    }
  }
}

variables {
  name                        = "example"
  environment                 = "integration"
  bucket_regional_domain_name = "example-integration-123456789012.s3.us-east-1.amazonaws.com"
  tags                        = { Environment = "integration" }
}

run "distribution_is_named_tagged_and_modern" {
  command = apply

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "example-integration" && aws_cloudfront_distribution.this.tags["Name"] == "example-integration" && aws_cloudfront_distribution.this.tags["Environment"] == "integration"
    error_message = "The distribution is named from name and environment and carries the tags input."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.enabled && aws_cloudfront_distribution.this.is_ipv6_enabled && aws_cloudfront_distribution.this.http_version == "http2and3"
    error_message = "The distribution is enabled, has IPv6 and serves HTTP/2 and HTTP/3."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.price_class == "PriceClass_100"
    error_message = "The default price class is PriceClass_100."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_root_object == null || aws_cloudfront_distribution.this.default_root_object == ""
    error_message = "default_root_object stays unset; the rewrite function handles /."
  }
}

run "name_suffix_extends_every_name" {
  command = plan

  variables {
    name_suffix = "web"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "example-integration-web" && aws_cloudfront_origin_access_control.this.name == "example-integration-web" && aws_cloudfront_function.spa_rewrite.name == "example-integration-web-spa-rewrite" && aws_cloudfront_response_headers_policy.this.name == "example-integration-web"
    error_message = "A suffix is the last part of every resource name."
  }
}

run "empty_environment_is_left_out_of_the_name" {
  command = plan

  variables {
    environment = ""
  }

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "example"
    error_message = "An empty environment must not leave a dangling hyphen."
  }
}

run "origin_access_control_signs_s3_requests_always" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.this.origin_access_control_origin_type == "s3" && aws_cloudfront_origin_access_control.this.signing_behavior == "always" && aws_cloudfront_origin_access_control.this.signing_protocol == "sigv4"
    error_message = "The origin access control signs every S3 request with sigv4."
  }
}

run "default_behaviour_serves_the_bucket_through_the_rewrite_function" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.this.origin) == 1 && one(aws_cloudfront_distribution.this.origin).domain_name == var.bucket_regional_domain_name
    error_message = "Without backends the only origin is the bucket."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).origin_id == one(aws_cloudfront_distribution.this.default_cache_behavior).target_origin_id
    error_message = "The default behaviour targets the S3 origin."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).origin_access_control_id == aws_cloudfront_origin_access_control.this.id
    error_message = "The S3 origin uses the origin access control."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).viewer_protocol_policy == "redirect-to-https" && one(aws_cloudfront_distribution.this.default_cache_behavior).compress
    error_message = "The default behaviour redirects to HTTPS and compresses."
  }

  assert {
    condition     = toset(one(aws_cloudfront_distribution.this.default_cache_behavior).allowed_methods) == toset(["GET", "HEAD", "OPTIONS"]) && toset(one(aws_cloudfront_distribution.this.default_cache_behavior).cached_methods) == toset(["GET", "HEAD"])
    error_message = "The default behaviour allows GET, HEAD and OPTIONS and caches GET and HEAD."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).cache_policy_id == data.aws_cloudfront_cache_policy.caching_optimized.id && data.aws_cloudfront_cache_policy.caching_optimized.name == "Managed-CachingOptimized"
    error_message = "The default behaviour uses the managed CachingOptimized policy."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).response_headers_policy_id == aws_cloudfront_response_headers_policy.this.id
    error_message = "The default behaviour uses the response headers policy."
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association).event_type == "viewer-request" && one(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association).function_arn == aws_cloudfront_function.spa_rewrite.arn
    error_message = "The default behaviour carries the SPA rewrite function on viewer request."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 0
    error_message = "Without backends there are no ordered behaviours."
  }
}

run "spa_rewrite_function_is_cloudfront_js_2_and_rewrites_extensionless_uris" {
  command = plan

  assert {
    condition     = aws_cloudfront_function.spa_rewrite.runtime == "cloudfront-js-2.0" && aws_cloudfront_function.spa_rewrite.publish
    error_message = "The rewrite function runs on cloudfront-js-2.0 and is published."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.spa_rewrite.code, "request.uri = '/index.html'") && strcontains(aws_cloudfront_function.spa_rewrite.code, "\\.[^/]+$")
    error_message = "The function rewrites a URI with no file extension to /index.html."
  }
}

run "response_headers_policy_carries_the_security_headers" {
  command = plan

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).content_security_policy).content_security_policy == var.content_security_policy && !one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).content_security_policy).override
    error_message = "The CSP is set without overriding one the origin sends."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).content_type_options).override
    error_message = "X-Content-Type-Options is set."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).frame_options).frame_option == "DENY"
    error_message = "Framing is denied."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).referrer_policy).referrer_policy == "strict-origin-when-cross-origin"
    error_message = "The referrer policy is strict-origin-when-cross-origin."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).strict_transport_security).access_control_max_age_sec == 63072000 && one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).strict_transport_security).include_subdomains && one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).strict_transport_security).preload
    error_message = "HSTS lasts two years and covers subdomains and preload."
  }
}

run "content_security_policy_can_be_replaced" {
  command = plan

  variables {
    content_security_policy = "default-src 'none'"
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.this.security_headers_config).content_security_policy).content_security_policy == "default-src 'none'"
    error_message = "content_security_policy replaces the default."
  }
}

run "default_policy_is_strict" {
  command = plan

  assert {
    condition     = strcontains(var.content_security_policy, "default-src 'self'") && strcontains(var.content_security_policy, "frame-ancestors 'none'") && strcontains(var.content_security_policy, "object-src 'none'") && !strcontains(var.content_security_policy, "unsafe")
    error_message = "The default CSP allows only the origin itself and no unsafe sources."
  }
}

run "no_aliases_and_no_certificate_use_the_default_certificate" {
  command = plan

  assert {
    condition     = one(aws_cloudfront_distribution.this.viewer_certificate).cloudfront_default_certificate
    error_message = "Without a certificate the default CloudFront certificate is used."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.aliases) == 0
    error_message = "There are no aliases by default."
  }
}

run "certificate_enables_sni_with_tls_1_2_2021" {
  command = plan

  variables {
    aliases         = ["app.example.com"]
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.viewer_certificate).acm_certificate_arn == var.certificate_arn && one(aws_cloudfront_distribution.this.viewer_certificate).ssl_support_method == "sni-only" && one(aws_cloudfront_distribution.this.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021"
    error_message = "A certificate is served with SNI and TLSv1.2_2021."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["app.example.com"])
    error_message = "The aliases input sets the distribution aliases."
  }
}

run "aliases_without_certificate_fail_the_precondition" {
  command = plan

  variables {
    aliases = ["app.example.com"]
  }

  expect_failures = [aws_cloudfront_distribution.this]
}

run "certificate_without_aliases_is_allowed" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.viewer_certificate).ssl_support_method == "sni-only"
    error_message = "A certificate without aliases is still used."
  }
}

run "web_acl_is_absent_by_default_and_attached_when_given" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == null || aws_cloudfront_distribution.this.web_acl_id == ""
    error_message = "No web ACL is attached by default."
  }
}

run "web_acl_arn_is_attached" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/example-integration/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == var.web_acl_arn
    error_message = "web_acl_arn is passed to the distribution."
  }
}

run "geo_restriction_is_off_for_an_empty_list" {
  command = plan

  assert {
    condition     = one(one(aws_cloudfront_distribution.this.restrictions).geo_restriction).restriction_type == "none" && length(one(one(aws_cloudfront_distribution.this.restrictions).geo_restriction).locations) == 0
    error_message = "An empty allowed_countries means no geo restriction."
  }
}

run "geo_restriction_is_a_whitelist_for_a_list" {
  command = plan

  variables {
    allowed_countries = ["IE", "GB"]
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.this.restrictions).geo_restriction).restriction_type == "whitelist" && one(one(aws_cloudfront_distribution.this.restrictions).geo_restriction).locations == toset(["IE", "GB"])
    error_message = "A non-empty allowed_countries is a whitelist."
  }
}

run "price_class_can_be_changed" {
  command = plan

  variables {
    price_class = "PriceClass_All"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.price_class == "PriceClass_All"
    error_message = "price_class sets the price class."
  }
}

run "access_logs_are_absent_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.access) == 0 && length(aws_cloudwatch_log_delivery_source.access) == 0 && length(aws_cloudwatch_log_delivery_destination.access) == 0 && length(aws_cloudwatch_log_delivery.access) == 0
    error_message = "Without access_logs no log group or delivery is created."
  }
}

run "access_logs_deliver_json_to_an_encrypted_log_group" {
  command = apply

  variables {
    access_logs = {
      kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.access[0].name == "/aws/cloudfront/example-integration" && aws_cloudwatch_log_group.access[0].kms_key_id == var.access_logs.kms_key_arn && aws_cloudwatch_log_group.access[0].retention_in_days == 7
    error_message = "The log group is named after the distribution, encrypted with the given key and kept for 7 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.access[0].tags["Environment"] == "integration"
    error_message = "The log group carries the tags input."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.access[0].log_type == "ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.access[0].resource_arn == aws_cloudfront_distribution.this.arn
    error_message = "The delivery source is the access logs of this distribution."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.access[0].output_format == "json" && one(aws_cloudwatch_log_delivery_destination.access[0].delivery_destination_configuration).destination_resource_arn == aws_cloudwatch_log_group.access[0].arn
    error_message = "The destination is the log group, in JSON."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.access[0].delivery_source_name == aws_cloudwatch_log_delivery_source.access[0].name && aws_cloudwatch_log_delivery.access[0].delivery_destination_arn == aws_cloudwatch_log_delivery_destination.access[0].arn
    error_message = "The delivery joins the source and the destination."
  }

  assert {
    condition     = !contains(aws_cloudwatch_log_delivery.access[0].record_fields, "cs-uri-query") && !contains(aws_cloudwatch_log_delivery.access[0].record_fields, "cs(Referer)") && !contains(aws_cloudwatch_log_delivery.access[0].record_fields, "cs(Cookie)")
    error_message = "Query string, referer and cookie are left out of the access logs on purpose."
  }

  assert {
    condition     = contains(aws_cloudwatch_log_delivery.access[0].record_fields, "c-ip") && contains(aws_cloudwatch_log_delivery.access[0].record_fields, "cs-uri-stem") && contains(aws_cloudwatch_log_delivery.access[0].record_fields, "sc-status") && length(aws_cloudwatch_log_delivery.access[0].record_fields) == 16
    error_message = "The access logs carry the 16 fields of the reference list."
  }
}

run "access_log_retention_can_be_changed" {
  command = plan

  variables {
    access_logs = {
      kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
      retention_days = 30
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.access[0].retention_in_days == 30
    error_message = "retention_days sets the log group retention."
  }
}

run "two_backends_with_the_same_origin_share_one_origin_block" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
      auth = {
        path_pattern       = "/auth/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.origin) == 2
    error_message = "The bucket and one shared backend origin make two origins."
  }

  assert {
    condition     = length([for o in aws_cloudfront_distribution.this.origin : o if length(o.vpc_origin_config) == 1]) == 1
    error_message = "Backends with the same VPC origin and domain share one origin block."
  }

  assert {
    condition     = length(distinct([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.target_origin_id])) == 1
    error_message = "Both behaviours target the shared origin."
  }

  assert {
    condition     = [for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.path_pattern] == ["/api/*", "/auth/*"]
    error_message = "Behaviours follow the order of the backend keys."
  }
}

run "backends_with_different_origins_get_one_origin_each" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
      reports = {
        path_pattern       = "/reports/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "reports.example.com"
      }
      other = {
        path_pattern       = "/other/*"
        vpc_origin_id      = "vo-0fedcba9876543210"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.origin) == 4
    error_message = "Each distinct pair of VPC origin and domain gets an origin, plus the bucket."
  }

  assert {
    condition     = length(distinct([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.target_origin_id])) == 3
    error_message = "The behaviours target three different origins."
  }
}

run "backend_behaviour_is_https_only_uncached_and_compressed" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 1 && aws_cloudfront_distribution.this.ordered_cache_behavior[0].path_pattern == "/api/*"
    error_message = "One backend makes one ordered behaviour on its path pattern."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].viewer_protocol_policy == "https-only" && aws_cloudfront_distribution.this.ordered_cache_behavior[0].compress
    error_message = "Backend behaviours accept only HTTPS and compress."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].cache_policy_id == data.aws_cloudfront_cache_policy.caching_disabled.id && data.aws_cloudfront_cache_policy.caching_disabled.name == "Managed-CachingDisabled"
    error_message = "Backend behaviours use the managed CachingDisabled policy."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this.ordered_cache_behavior[0].allowed_methods) == toset(["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"])
    error_message = "Backends allow all seven methods by default."
  }

  assert {
    condition     = data.aws_cloudfront_origin_request_policy.managed["AllViewerExceptHostHeader"].name == "Managed-AllViewerExceptHostHeader" && aws_cloudfront_distribution.this.ordered_cache_behavior[0].origin_request_policy_id == data.aws_cloudfront_origin_request_policy.managed["AllViewerExceptHostHeader"].id
    error_message = "The default origin request policy is AllViewerExceptHostHeader."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].response_headers_policy_id == aws_cloudfront_response_headers_policy.this.id
    error_message = "Backend behaviours use the response headers policy."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior[0].function_association) == 0
    error_message = "A backend without function code has no function association."
  }

  assert {
    condition     = length(aws_cloudfront_function.backend) == 0
    error_message = "A backend without function code creates no function."
  }
}

run "backend_origin_uses_the_vpc_origin_and_domain" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  assert {
    condition     = [for o in aws_cloudfront_distribution.this.origin : o.domain_name if length(o.vpc_origin_config) == 1] == ["origin.example.com"]
    error_message = "The backend origin uses origin_domain_name as its domain."
  }

  assert {
    condition     = [for o in aws_cloudfront_distribution.this.origin : one(o.vpc_origin_config).vpc_origin_id if length(o.vpc_origin_config) == 1] == ["vo-0123456789abcdef0"]
    error_message = "The backend origin points at the VPC origin."
  }

  assert {
    condition     = [for o in aws_cloudfront_distribution.this.origin : one(o.vpc_origin_config).origin_read_timeout if length(o.vpc_origin_config) == 1] == [30]
    error_message = "The origin read timeout is 30 seconds."
  }
}

run "backend_with_function_code_creates_and_associates_a_function" {
  command = apply

  variables {
    backends = {
      api = {
        path_pattern                 = "/api/*"
        vpc_origin_id                = "vo-0123456789abcdef0"
        origin_domain_name           = "origin.example.com"
        viewer_request_function_code = "function handler(event) { return event.request; }"
      }
      auth = {
        path_pattern       = "/auth/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_function.backend) == 1 && aws_cloudfront_function.backend["api"].name == "example-integration-api" && aws_cloudfront_function.backend["api"].runtime == "cloudfront-js-2.0" && aws_cloudfront_function.backend["api"].publish
    error_message = "Only the backend with function code gets a published cloudfront-js-2.0 function."
  }

  assert {
    condition     = aws_cloudfront_function.backend["api"].code == "function handler(event) { return event.request; }"
    error_message = "The function runs the code the backend gave."
  }

  assert {
    condition     = [for b in aws_cloudfront_distribution.this.ordered_cache_behavior : length(b.function_association) if b.path_pattern == "/api/*"] == [1] && [for b in aws_cloudfront_distribution.this.ordered_cache_behavior : length(b.function_association) if b.path_pattern == "/auth/*"] == [0]
    error_message = "Only the behaviour whose backend sets function code is associated with a function."
  }

  assert {
    condition     = [for b in aws_cloudfront_distribution.this.ordered_cache_behavior : one(b.function_association).event_type if b.path_pattern == "/api/*"] == ["viewer-request"]
    error_message = "The backend function runs on viewer request."
  }
}

run "backend_methods_and_origin_request_policy_can_be_changed" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern          = "/api/*"
        vpc_origin_id         = "vo-0123456789abcdef0"
        origin_domain_name    = "origin.example.com"
        allowed_methods       = ["GET", "HEAD"]
        origin_request_policy = "AllViewer"
      }
    }
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this.ordered_cache_behavior[0].allowed_methods) == toset(["GET", "HEAD"])
    error_message = "allowed_methods is used as given."
  }

  assert {
    condition     = data.aws_cloudfront_origin_request_policy.managed["AllViewer"].name == "Managed-AllViewer"
    error_message = "origin_request_policy names a managed policy without the prefix."
  }
}

run "outputs_expose_the_distribution_and_access_control" {
  command = apply

  assert {
    condition     = output.distribution_id == aws_cloudfront_distribution.this.id && output.distribution_arn == aws_cloudfront_distribution.this.arn && output.distribution_domain_name == aws_cloudfront_distribution.this.domain_name && output.distribution_hosted_zone_id == aws_cloudfront_distribution.this.hosted_zone_id && output.origin_access_control_id == aws_cloudfront_origin_access_control.this.id
    error_message = "Outputs must point at the distribution and the origin access control."
  }
}

run "price_class_outside_the_list_is_rejected" {
  command = plan

  variables {
    price_class = "PriceClass_50"
  }

  expect_failures = [var.price_class]
}

run "malformed_country_code_is_rejected" {
  command = plan

  variables {
    allowed_countries = ["ireland"]
  }

  expect_failures = [var.allowed_countries]
}

run "backend_path_without_leading_slash_is_rejected" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  expect_failures = [var.backends]
}

run "backend_origin_on_the_elb_domain_is_rejected" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "internal-example-123456.eu-west-1.elb.amazonaws.com"
      }
    }
  }

  expect_failures = [var.backends]
}

run "backends_sharing_a_path_are_rejected" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
      api_v2 = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  expect_failures = [var.backends]
}

run "backend_key_with_a_space_is_rejected" {
  command = plan

  variables {
    backends = {
      "my api" = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
      }
    }
  }

  expect_failures = [var.backends]
}

run "unsupported_method_set_is_rejected" {
  command = plan

  variables {
    backends = {
      api = {
        path_pattern       = "/api/*"
        vpc_origin_id      = "vo-0123456789abcdef0"
        origin_domain_name = "origin.example.com"
        allowed_methods    = ["GET", "POST"]
      }
    }
  }

  expect_failures = [var.backends]
}
