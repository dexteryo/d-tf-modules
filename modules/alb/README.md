# alb

One external application load balancer with its security group, HTTPS listeners and optional header-based forwarding rules.

## Owns

- `aws_lb` named `<name>-<environment>` (at most 32 characters) with invalid header dropping and deletion protection on.
- Its security group, through `../security-group`, with ingress options: `cloudfront_only`, `ingress_cidrs` and `ingress_prefix_list_ids`.
- HTTPS listeners (`listeners`). A listener without `default_target_group_arn` answers every request with a fixed `403`, so a request reaches a service only through a rule.
- Header forwarding rules (`header_forward_rules` and the sensitive `header_values`).

## Does not own

- Target groups and per-service listener rules; `ecs-service` creates them against a listener ARN from `listener_arns`.
- Certificates, DNS records, WAF, CloudFront distributions and the access log bucket.
- The security group of the services behind it.

## Usage

```hcl
module "alb" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/alb?ref=v0.2.0"

  name         = "ordering"
  environment  = "integration"
  vpc_id       = var.vpc_id
  subnet_ids   = var.public_subnet_ids
  tags         = module.tags.all_tags
  idle_timeout = 120

  cloudfront_only = true

  listeners = {
    https = {
      port            = 443
      certificate_arn = var.certificate_arn
    }
  }

  egress_rules = {
    to-tasks = {
      description                  = "Application port of the tasks"
      from_port                    = 8788
      to_port                      = 8788
      referenced_security_group_id = module.task_security_group.security_group_id
    }
  }
}
```

## CloudFront only

`cloudfront_only = true` accepts traffic on `ingress_port` (443) from the AWS-managed CloudFront origin-facing prefix list and from nothing else. That list covers every CloudFront distribution, so also forward only requests that carry a secret header that your distribution adds:

```hcl
header_forward_rules = {
  from-edge = {
    listener         = "https"
    priority         = 10
    header_name      = "X-Origin-Verify"
    target_group_arn = module.service.target_group_arn
  }
}
header_values = { from-edge = random_password.origin_verify.result }
```

The header value is passed separately because it is sensitive and `for_each` keys cannot be.

## Defaults worth knowing

- The security group has no ingress unless you choose an option, and no egress unless you list `egress_rules`. Health checks and forwarding need an egress rule to the service group.
- TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`; listeners are HTTPS only.
- `internal = false`: this is the external load balancer. Trivy rule `AWS-0053` (publicly exposed load balancer) is therefore listed in `.trivyignore`: the group is closed until an ingress option is set and the listeners return 403 without a matching rule. Set `internal = true` for a private load balancer.

## Left out of the reference shape

The reference module chunks very long CIDR lists over several security groups, creates one group per prefix list, defaults egress to everywhere, forwards by default from the listener, ships a default TLS policy as a variable only, and carries a CDN-vendor prefix list name. This module keeps the CIDR and prefix list ingress inputs, always uses one group, closes the default action and offers the CloudFront option instead of a vendor list.

## Tests

`terraform test` with `mock_provider "aws"` covers secure defaults, the closed security group, CloudFront-only ingress (prefix list, port 443, no other source), CIDR and prefix list ingress, listed egress, the 403 default action, forwarding to a default target group, the header rule, access logs, idle timeout and the name and subnet validations.

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

| Name | Source | Version |
| ---- | ------ | ------- |
| security\_group | ../security-group | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.header_forward](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_ec2_managed_prefix_list.cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| name | Workload name. The load balancer is named <name>-<environment>, at most 32 characters | `string` | n/a | yes |
| subnet\_ids | Subnets of the load balancer, in at least two availability zones | `list(string)` | n/a | yes |
| vpc\_id | VPC of the load balancer and its security group | `string` | n/a | yes |
| access\_logs | Write access logs to an S3 bucket the load balancer may write to. The bucket and its policy are not created here | ```object({ bucket = string prefix = optional(string) })``` | `null` | no |
| cloudfront\_only | Accept traffic from CloudFront's origin-facing prefix list only. Combine with a secret header rule so other CloudFront distributions cannot reach the origin | `bool` | `false` | no |
| drop\_invalid\_header\_fields | Drop requests with malformed HTTP header fields | `bool` | `true` | no |
| egress\_rules | Outbound rules of the load balancer security group, same shape as in the security-group module. List the target security group and port of every service the load balancer forwards to | ```map(object({ description = string protocol = optional(string, "tcp") from_port = optional(number) to_port = optional(number) cidr_ipv4 = optional(string) cidr_ipv6 = optional(string) prefix_list_id = optional(string) referenced_security_group_id = optional(string) }))``` | `{}` | no |
| enable\_deletion\_protection | Refuse to delete the load balancer until the protection is turned off | `bool` | `true` | no |
| header\_forward\_rules | Rules that forward requests carrying a given header to a target group. The header value comes from header\_values under the same key | ```map(object({ listener = string priority = number header_name = string target_group_arn = string }))``` | `{}` | no |
| header\_values | Secret header values of header\_forward\_rules, keyed like the rules | `map(string)` | `{}` | no |
| idle\_timeout | Seconds a connection may stay idle. Raise it for server-sent events | `number` | `60` | no |
| ingress\_cidrs | IPv4 ranges that may reach the load balancer | `list(string)` | `[]` | no |
| ingress\_port | Port the ingress options below open | `number` | `443` | no |
| ingress\_prefix\_list\_ids | Managed prefix lists that may reach the load balancer | `list(string)` | `[]` | no |
| internal | Create an internal load balancer instead of an internet-facing one | `bool` | `false` | no |
| listeners | HTTPS listeners keyed by a name that stays the same between runs. Without default\_target\_group\_arn the listener answers every request with a fixed 403, so a request only reaches a service through a rule | ```map(object({ port = number certificate_arn = string ssl_policy = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06") default_target_group_arn = optional(string) }))``` | `{}` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_arn | ARN of the load balancer |
| alb\_arn\_suffix | ARN suffix for CloudWatch dimensions |
| alb\_dns\_name | DNS name of the load balancer |
| alb\_security\_group\_id | Security group of the load balancer; reference it from the security group of the service |
| alb\_zone\_id | Route 53 zone id of the load balancer, for alias records |
| egress\_rules | Egress rules of the load balancer security group |
| header\_forward\_rules | Header name and value each rule matches, keyed like the header\_forward\_rules input |
| ingress\_rules | Ingress rules of the load balancer security group |
| listener\_arns | Listener ARNs keyed like the listeners input |
| listeners | Port, protocol, TLS policy and default action of every listener, keyed like the listeners input |
| load\_balancer | Settings of the load balancer as created, for review and for tests in the calling configuration |
<!-- END_TF_DOCS -->