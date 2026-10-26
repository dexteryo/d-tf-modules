# security-group

One security group whose rules are inputs. Nothing is open until a rule says so.

## Owns

- `aws_security_group` named from `<name>-<environment>[-<name_suffix>]` (as a name prefix, so a replacement can be created before the old group is destroyed).
- Ingress and egress rules as separate `aws_vpc_security_group_*_rule` resources, one per key of `ingress_rules` and `egress_rules`.

## Does not own

- The resources the group is attached to. `ecs-service` and `alb` take a group id.
- Rules that belong to the other side of a connection. A service group lists the load balancer group as an ingress source; the load balancer group lists the service group as an egress destination.

## Usage

```hcl
module "task_security_group" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/security-group?ref=v0.5.1"

  name        = "ordering"
  environment = "integration"
  vpc_id      = var.vpc_id
  tags        = module.tags.all_tags

  ingress_rules = {
    from-alb = {
      description                  = "Application port from the load balancer"
      from_port                    = 8788
      to_port                      = 8788
      referenced_security_group_id = module.alb.alb_security_group_id
    }
  }

  egress_rules = {
    https = {
      description = "HTTPS to the VPC endpoints"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "10.0.0.0/16"
    }
  }
}
```

## Defaults worth knowing

- No egress by default. Terraform removes the allow-all egress rule AWS adds to a new group, so tasks cannot reach anything until you list it.
- Every rule needs exactly one source or destination: `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id` or `referenced_security_group_id`.
- Rule keys must stay the same between runs; they become the resource addresses.
- The module contains no CIDR literal, so trivy rule `AWS-0104` (egress to `0.0.0.0/0`) only fires in a caller that passes such a rule.

## Left out of the reference shape

The reference "standard" group is a fixed list of egress destinations for one organisation's security agents, proxy and log forwarder. That is a policy for that estate, not a pattern to copy. The shape that is kept: a small module that owns one group and nothing else, with tags passed in.

## Tests

`terraform test` with `mock_provider "aws"` covers the closed default, naming, ingress only from a referenced group (no CIDR, one port, TCP), prefix list sources, egress rules, and the one-source and port validations.

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
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| name | Workload name. The security group is named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| vpc\_id | VPC the security group is created in | `string` | n/a | yes |
| description | Description of the security group. Defaults to a sentence built from the name | `string` | `null` | no |
| egress\_rules | Outbound rules, same shape as ingress\_rules. The default is no outbound traffic at all, so list every destination | ```map(object({ description = string protocol = optional(string, "tcp") from_port = optional(number) to_port = optional(number) cidr_ipv4 = optional(string) cidr_ipv6 = optional(string) prefix_list_id = optional(string) referenced_security_group_id = optional(string) }))``` | `{}` | no |
| ingress\_rules | Inbound rules keyed by a name that stays the same between runs. Give exactly one source per rule: cidr\_ipv4, cidr\_ipv6, prefix\_list\_id or referenced\_security\_group\_id. Leave ports empty for protocol -1 | ```map(object({ description = string protocol = optional(string, "tcp") from_port = optional(number) to_port = optional(number) cidr_ipv4 = optional(string) cidr_ipv6 = optional(string) prefix_list_id = optional(string) referenced_security_group_id = optional(string) }))``` | `{}` | no |
| name\_suffix | Optional last part of the name, for example alb or tasks | `string` | `""` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| egress\_rules | The egress rules as created, keyed like the input |
| ingress\_rules | The ingress rules as created, keyed like the input |
| security\_group\_arn | ARN of the security group |
| security\_group\_id | ID of the security group |
| security\_group\_name | Name AWS generated from the name prefix |
<!-- END_TF_DOCS -->