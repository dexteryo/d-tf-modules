data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

locals {
  full_name    = join("-", compact([var.name, var.environment, var.name_suffix]))
  s3_origin_id = "app-bucket"
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = local.full_name
  description                       = "Reads the ${local.full_name} app bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${local.full_name}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Serves index.html for app routes, which have no file extension"
  publish = true
  code    = file("${path.module}/functions/spa-rewrite.js")
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name = local.full_name

  security_headers_config {
    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = false
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = local.full_name
  aliases         = var.aliases
  price_class     = var.price_class
  web_acl_id      = var.web_acl_arn
  http_version    = "http2and3"

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = var.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  dynamic "origin" {
    for_each = local.backend_origins

    content {
      origin_id   = origin.value.origin_id
      domain_name = origin.value.origin_domain_name

      vpc_origin_config {
        vpc_origin_id            = origin.value.vpc_origin_id
        origin_read_timeout      = 30
        origin_keepalive_timeout = 5
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.backends

    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = local.backend_origin_ids[ordered_cache_behavior.key]
      viewer_protocol_policy     = "https-only"
      allowed_methods            = ordered_cache_behavior.value.allowed_methods
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
      origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.managed[ordered_cache_behavior.value.origin_request_policy].id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id

      dynamic "function_association" {
        for_each = contains(keys(local.backend_functions), ordered_cache_behavior.key) ? [ordered_cache_behavior.key] : []

        content {
          event_type   = "viewer-request"
          function_arn = aws_cloudfront_function.backend[function_association.value].arn
        }
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = length(var.allowed_countries) == 0 ? "none" : "whitelist"
      locations        = var.allowed_countries
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.certificate_arn == null ? [1] : []

    content {
      cloudfront_default_certificate = true
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.certificate_arn == null ? [] : [var.certificate_arn]

    content {
      acm_certificate_arn      = viewer_certificate.value
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  tags = merge(var.tags, { Name = local.full_name })

  lifecycle {
    precondition {
      condition     = length(var.aliases) == 0 || var.certificate_arn != null
      error_message = "certificate_arn is required when aliases is not empty."
    }
  }
}
