# cloudfront-spa

One CloudFront distribution that serves a single-page app from a private S3 bucket through origin access control, with route rewriting, security headers, optional access logs and optional backend paths that go to an internal load balancer through a CloudFront VPC origin.

## Owns

- The distribution, with IPv6, HTTP/2 and HTTP/3, and TLS `TLSv1.2_2021` with SNI when a certificate is given.
- The origin access control (`sigv4`, always) for the S3 origin.
- The default behaviour: the bucket, redirect to HTTPS, GET, HEAD and OPTIONS, compression, the managed CachingOptimized policy, the response headers policy and a viewer-request function that turns any URI without a file extension into `/index.html`. `default_root_object` is left unset because that function also handles `/`.
- The response headers policy: your CSP (not overriding one the origin sends), `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin` and HSTS for two years with subdomains and preload.
- One ordered behaviour per entry in `backends`: HTTPS only, caching disabled, compression on, the same response headers policy. Backends with the same `vpc_origin_id` and `origin_domain_name` share one origin.
- One CloudFront Function per backend that sets `viewer_request_function_code`.
- When `access_logs` is set: the log group `/aws/cloudfront/<name>-<environment>[-<name_suffix>]`, encrypted with the given key, and the log delivery source, destination and delivery that send access logs there as JSON.

## Does not own

- The bucket. Create it with `modules/s3-bucket` and pass its `bucket_regional_domain_name`.
- The bucket policy that lets the distribution read. `modules/s3-bucket` writes it when you pass this module's `distribution_arn` as `cloudfront_distribution_arn`.
- The key policy for the bucket's KMS key. See [Origin access control wiring](#origin-access-control-wiring).
- The ACM certificate (in `us-east-1`), DNS records, the web ACL (`modules/waf-web-acl`), the CloudFront VPC origin and the internal load balancer.
- The content of the bucket. Deploy the build to it from your pipeline.

## Provider

CloudFront certificates, web ACLs and access log delivery all live in `us-east-1`. Call the module with a provider for that region:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

The module declares no `configuration_aliases`; pass `providers = { aws = aws.us_east_1 }` as in the usage below. The bucket can be in another region.

## Usage

```hcl
module "web" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/cloudfront-spa?ref=v0.4.0"

  providers = { aws = aws.us_east_1 }

  name                        = "ordering"
  environment                 = "production"
  bucket_regional_domain_name = module.web_bucket.bucket_regional_domain_name
  aliases                     = ["app.example.com"]
  certificate_arn             = aws_acm_certificate.app.arn
  web_acl_arn                 = module.web_acl.web_acl_arn
  allowed_countries           = ["IE", "GB"]

  access_logs = {
    kms_key_arn = module.edge_logs_key.kms_key_arn
  }

  backends = {
    api = {
      path_pattern       = "/api/*"
      vpc_origin_id      = aws_cloudfront_vpc_origin.alb.id
      origin_domain_name = "origin.example.com"
    }
  }

  tags = module.tags.all_tags
}
```

## Origin access control wiring

The bucket and its key must both trust this distribution, and each is a separate resource you own:

1. Create the bucket with `modules/s3-bucket`, passing `cloudfront_distribution_arn = module.web.distribution_arn`. That adds an `s3:GetObject` statement for `cloudfront.amazonaws.com` conditioned on `AWS:SourceArn` being the distribution.
2. Give the bucket's KMS key a `service_grants` entry for `cloudfront.amazonaws.com` with `actions = ["kms:Decrypt"]`. Condition it on `aws:SourceArn`. The key must exist before the bucket and the bucket before the distribution, so it cannot name the distribution's own ARN without a dependency cycle; use `arn:aws:cloudfront::<account id>:distribution/*` as `examples/basic` does. The bucket policy still limits reads to this one distribution.

Without the key grant every request for an object returns 403.

## Backends

`backends` is a map keyed by a stable name. The key becomes the function name suffix, so it may only hold letters, digits, hyphens and underscores. Behaviours are created in the order of the keys, and CloudFront matches the first path pattern that fits, so name keys with that in mind or keep patterns that do not overlap. Each `path_pattern` must be unique and start with `/`.

`origin_domain_name` must be a custom DNS name covered by the load balancer's listener certificate; CloudFront checks the certificate against it. A name ending in `.elb.amazonaws.com` is rejected because no ACM certificate can match it. `allowed_methods` is one of the three sets CloudFront accepts: GET and HEAD, those plus OPTIONS, or all seven. `origin_request_policy` is the name of a managed policy without the `Managed-` prefix, for example `AllViewerExceptHostHeader` (the default) or `AllViewer`.

## Defaults worth knowing

- `aliases` is empty and `certificate_arn` is null, so the distribution answers only on its `*.cloudfront.net` name with the default certificate and cannot negotiate `TLSv1.2_2021`. Setting `aliases` without a certificate fails at plan time.
- No web ACL, no access logs and no backends unless you set them.
- `allowed_countries` is empty, which means no geo restriction. A non-empty list is a whitelist: only those countries get through.
- `price_class` is `PriceClass_100` (North America and Europe).
- Access logs are kept for 7 days. The delivery omits the query string, referer and cookie on purpose, since they often carry tokens and personal data. The fields it keeps are timestamp, distribution ID, date, time, edge location, bytes, client IP, method, host, URI path, status, user agent, edge result type, request ID, protocol and time taken.
- The default CSP allows only the origin itself and no inline scripts or styles. Loosen it through `content_security_policy` for the sources your app really loads.

## Left out on purpose

Custom error responses, cache policies other than the managed ones, origin groups and failover, Lambda@Edge, key groups and signed URLs, field-level encryption, continuous deployment and standard (S3) access logs. The S3 origin and the load balancer already span several zones, and the v2 log delivery supports customer-managed keys where the legacy one does not.

## Tests

`terraform test` with `mock_provider "aws"` covers naming and tags, the origin access control, the default behaviour (S3 origin, cache policy, response headers policy and rewrite function), the headers policy, the certificate with and without aliases and its precondition, the web ACL, geo restriction on and off, price class, access logs on and off, shared and separate backend origins, backend behaviour settings, backend functions with and without code, the outputs and input validation.

## Example

`examples/basic` in this directory composes `tags`, `kms`, `s3-bucket` and `waf-web-acl` with this module, including the key policy and bucket policy for origin access control. It validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_function.spa_rewrite](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_origin_access_control.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_cloudfront_response_headers_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_response_headers_policy) | resource |
| [aws_cloudwatch_log_delivery.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery) | resource |
| [aws_cloudwatch_log_delivery_destination.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery_destination) | resource |
| [aws_cloudwatch_log_delivery_source.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery_source) | resource |
| [aws_cloudwatch_log_group.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudfront_cache_policy.caching_disabled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_cloudfront_cache_policy.caching_optimized](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_cloudfront_origin_request_policy.managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_origin_request_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_regional\_domain\_name | Regional domain name of the private S3 bucket that holds the app build, the bucket\_regional\_domain\_name output of modules/s3-bucket | `string` | n/a | yes |
| name | Workload name. Resources are named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| access\_logs | Send access logs to a KMS-encrypted CloudWatch log group. kms\_key\_arn is a key in us-east-1 that logs.us-east-1.amazonaws.com may use. Null means no access logs | ```object({ kms_key_arn = string retention_days = optional(number, 7) })``` | `null` | no |
| aliases | Host names the distribution serves. Needs certificate\_arn when not empty | `list(string)` | `[]` | no |
| allowed\_countries | ISO 3166-1 alpha-2 country codes allowed through, for example ["IE", "GB"]. An empty list means no geo restriction | `list(string)` | `[]` | no |
| backends | Paths served by an internal load balancer through a CloudFront VPC origin, keyed by a stable name that is also the function name suffix (letters, digits, hyphens, underscores). path\_pattern starts with /. origin\_domain\_name is a custom DNS name covered by the load balancer's listener certificate. Backends with the same vpc\_origin\_id and origin\_domain\_name share one origin. viewer\_request\_function\_code, when set, becomes a CloudFront Function on that behaviour. allowed\_methods is one of GET,HEAD / GET,HEAD,OPTIONS / all seven methods. origin\_request\_policy is the name of a managed origin request policy without the Managed- prefix. | ```map(object({ path_pattern = string vpc_origin_id = string origin_domain_name = string viewer_request_function_code = optional(string) allowed_methods = optional(list(string), ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]) origin_request_policy = optional(string, "AllViewerExceptHostHeader") }))``` | `{}` | no |
| certificate\_arn | ACM certificate in us-east-1 that covers every alias. Null uses the default CloudFront certificate, which only serves the *.cloudfront.net name | `string` | `null` | no |
| content\_security\_policy | Content-Security-Policy added to responses that do not carry their own | `string` | `"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"` | no |
| environment | Deployment environment, for example integration or production | `string` | `""` | no |
| name\_suffix | Optional last part of the name, for example web when one workload has several distributions | `string` | `""` | no |
| price\_class | CloudFront price class: PriceClass\_100, PriceClass\_200 or PriceClass\_All | `string` | `"PriceClass_100"` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| web\_acl\_arn | Web ACL to attach, usually the web\_acl\_arn output of modules/waf-web-acl. Null leaves the distribution without one | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| distribution\_arn | CloudFront distribution ARN, for cloudfront\_distribution\_arn of modules/s3-bucket and the aws:SourceArn condition of the key policy |
| distribution\_domain\_name | CloudFront domain name to point the DNS aliases at |
| distribution\_hosted\_zone\_id | Route 53 hosted zone ID of CloudFront, for alias records |
| distribution\_id | CloudFront distribution ID |
| origin\_access\_control\_id | ID of the origin access control that signs requests to the S3 bucket |
<!-- END_TF_DOCS -->
