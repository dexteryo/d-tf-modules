# waf-web-acl

One WAFv2 web ACL for CloudFront: AWS managed rule groups, an optional per-IP rate limit and logging to an encrypted CloudWatch log group with redacted fields.

## Owns

- The web ACL with scope `CLOUDFRONT` and a default action of allow.
- One rule per entry in `managed_rule_groups`, each keeping the group's own actions.
- An optional rate rule that blocks an IP after `rate_limit_per_5_minutes` requests in 5 minutes. Its priority is the highest group priority plus 10, so it always runs last.
- The log group `aws-waf-logs-<name>-<environment>[-<name_suffix>]`, encrypted with `kms_key_arn`, and the logging configuration that redacts the `authorization` and `cookie` headers, the URI path and the query string.

## Does not own

- The CloudFront distribution. Pass `web_acl_arn` to `modules/cloudfront-spa`, or to any other distribution.
- The KMS key. Create it with `modules/kms` in `us-east-1` and let `logs.us-east-1.amazonaws.com` use it, limited to the log group, as in `examples/basic`.
- Custom rules, IP allow-lists, geo rules and bot control. Geo restriction lives on the distribution (`allowed_countries` in `modules/cloudfront-spa`).

## Provider

A web ACL with scope `CLOUDFRONT` can only be created in `us-east-1`. Call the module with a provider for that region:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

The module declares no `configuration_aliases`; pass `providers = { aws = aws.us_east_1 }` as in the usage below.

## Usage

```hcl
module "web_acl" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/waf-web-acl?ref=v0.3.0"

  providers = { aws = aws.us_east_1 }

  name                     = "ordering"
  environment              = "production"
  kms_key_arn              = module.edge_logs_key.kms_key_arn
  rate_limit_per_5_minutes = 1000
  tags                     = module.tags.all_tags
}
```

## Defaults worth knowing

- The default rule groups and priorities are `AWSManagedRulesAmazonIpReputationList` 10, `AWSManagedRulesAnonymousIpList` 15, `AWSManagedRulesKnownBadInputsRuleSet` 20 and `AWSManagedRulesCommonRuleSet` 30. Setting `managed_rule_groups` replaces the whole list. Names and priorities must each be unique.
- The rate limit is 1000 requests per 5 minutes per IP. Set it to `null` to leave the rate rule out; otherwise it must be at least 10, the lowest limit WAF accepts.
- Logs are kept for 7 days because they hold client IPs.
- Every rule publishes CloudWatch metrics and samples requests. Metric names are `<full name>-<rule name>`.

## Left out on purpose

Per-rule overrides and excluded rules, rule labels, custom response bodies, scope-down statements, CAPTCHA and the regional scope. Each makes the input larger for callers that do not need it; add them when a workload does.

## Tests

`terraform test` with `mock_provider "aws"` covers naming and tags, the CLOUDFRONT scope, the default groups and priorities, the rate rule on, off and at its computed priority, a group from another vendor, the log group name, key and retention, header, path and query redaction on and off, the outputs and input validation.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

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
| [aws_cloudwatch_log_group.waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_wafv2_web_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_logging_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| kms\_key\_arn | Key in the module provider region (us-east-1) that encrypts the WAF log group | `string` | n/a | yes |
| name | Workload name. Resources are named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| environment | Deployment environment, for example integration or production | `string` | `""` | no |
| log\_retention\_days | Days to keep WAF logs in CloudWatch. They hold client IPs, so keep them short | `number` | `7` | no |
| managed\_rule\_groups | Managed rule groups to evaluate, each with a unique name and a unique priority. Lower priorities run first | ```list(object({ name = string priority = number vendor_name = optional(string, "AWS") }))``` | ```[ { "name": "AWSManagedRulesAmazonIpReputationList", "priority": 10 }, { "name": "AWSManagedRulesAnonymousIpList", "priority": 15 }, { "name": "AWSManagedRulesKnownBadInputsRuleSet", "priority": 20 }, { "name": "AWSManagedRulesCommonRuleSet", "priority": 30 } ]``` | no |
| name\_suffix | Optional last part of the name, for example edge when one workload has several web ACLs | `string` | `""` | no |
| rate\_limit\_per\_5\_minutes | Requests one IP may send in 5 minutes before WAF blocks it. Null turns the rate rule off. The rule runs after every managed rule group | `number` | `1000` | no |
| redact\_query\_string | Replace the query string in the WAF logs | `bool` | `true` | no |
| redact\_uri\_path | Replace the request path in the WAF logs | `bool` | `true` | no |
| redacted\_headers | Request headers whose values are replaced in the WAF logs | `list(string)` | ```[ "authorization", "cookie" ]``` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| log\_group\_arn | Log group that receives the WAF logs |
| web\_acl\_arn | ARN of the CloudFront web ACL, for the web\_acl\_arn input of modules/cloudfront-spa |
| web\_acl\_id | ID of the web ACL |
<!-- END_TF_DOCS -->
