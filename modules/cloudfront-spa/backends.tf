data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "managed" {
  for_each = toset([for backend in values(var.backends) : backend.origin_request_policy])

  name = "Managed-${each.value}"
}

locals {
  backend_origin_pairs = distinct([
    for backend in values(var.backends) : {
      vpc_origin_id      = backend.vpc_origin_id
      origin_domain_name = backend.origin_domain_name
    }
  ])

  backend_origins = {
    for pair in local.backend_origin_pairs :
    "${pair.vpc_origin_id}|${pair.origin_domain_name}" => merge(pair, {
      origin_id = "backend-${substr(sha1("${pair.vpc_origin_id}|${pair.origin_domain_name}"), 0, 8)}"
    })
  }

  backend_origin_ids = {
    for key, backend in var.backends :
    key => local.backend_origins["${backend.vpc_origin_id}|${backend.origin_domain_name}"].origin_id
  }

  backend_functions = {
    for key, backend in var.backends : key => backend.viewer_request_function_code
    if backend.viewer_request_function_code != null
  }
}

resource "aws_cloudfront_function" "backend" {
  for_each = local.backend_functions

  name    = "${local.full_name}-${each.key}"
  runtime = "cloudfront-js-2.0"
  comment = "Viewer request function of the ${each.key} backend"
  publish = true
  code    = each.value
}
