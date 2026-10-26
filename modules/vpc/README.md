# vpc

A three-tier VPC spread over 2 to 6 zones: public, private and isolated subnets, one NAT gateway and Elastic IP per zone, endpoints for AWS services, flow logs and a default security group that admits nothing.

## Owns

- The VPC, internet gateway, and one public, one private and one isolated subnet per zone.
- A NAT gateway and Elastic IP per zone. Each private subnet routes to the NAT gateway in its own zone, so losing a zone does not cut off the others.
- Route tables: one shared public table, one private table per zone, one shared isolated table with no route out.
- Gateway endpoints (`s3` by default, `dynamodb` on request) on the private and isolated route tables.
- Interface endpoints for the services in `interface_endpoint_services`, in the private subnets, behind one security group that admits HTTPS from the VPC.
- Flow logs for all traffic into a KMS-encrypted log group, with the role that writes them.
- The VPC's default security group, emptied.

## Does not own

- Workload security groups. Use `modules/security-group`, passing `vpc_id`.
- Load balancers. Use `modules/alb`, passing the public subnets, or build an internal one in the caller.
- The KMS key for the flow logs. Create it with `modules/kms` and let `logs.<region>.amazonaws.com` use it, as in `examples/basic`.

## Usage

```hcl
module "vpc" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/vpc?ref=v0.5.0"

  name                        = "ordering"
  environment                 = "production"
  cidr_block                  = "10.20.0.0/16"
  availability_zones          = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  logs_kms_key_arn            = module.logs_key.kms_key_arn
  interface_endpoint_services = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
  tags                        = module.tags.all_tags
}
```

## Subnet layout

The VPC must be a /16. Subnets are carved from it in fixed blocks, one per zone in the order of `availability_zones`:

| Tier | Size | Blocks (for `10.20.0.0/16`) |
| --- | --- | --- |
| public | /24 | `10.20.0.0` to `10.20.5.0` |
| isolated | /24 | `10.20.10.0` to `10.20.15.0` |
| private | /22 | `10.20.16.0` to `10.20.36.0` |

Private subnets are larger because tasks and endpoints take their addresses. The layout is fixed so that adding a zone never moves an existing subnet.

## Defaults worth knowing

- A NAT gateway per zone is the expensive part of this module, and there is no option for a single shared one. Use fewer zones if cost matters more than zone isolation.
- Nothing gets a public IP on launch, even in the public subnets.
- Flow logs are kept for 365 days.
- Output `nat_eips` is what partners put on their allow-lists. The addresses stay as long as the NAT gateways do.

## Left out on purpose

IPv6, a transit gateway or peering, network ACLs beyond the VPC defaults, and a single-NAT mode. Each can be added in the caller from the outputs.

## Tests

`terraform test` with `mock_provider "aws"` covers naming and tags, the fixed subnet CIDRs and zone order, a NAT gateway and private route per zone, the empty default security group, gateway and interface endpoints, flow logs, other zone counts and input validation.

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
| [aws_cloudwatch_log_group.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.isolated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.isolated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.isolated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.flow_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| availability\_zones | Zones to spread the subnets over, for example ["eu-west-1a", "eu-west-1b", "eu-west-1c"]. Each zone gets one public, one private and one isolated subnet and its own NAT gateway | `list(string)` | n/a | yes |
| logs\_kms\_key\_arn | Key that encrypts the VPC flow log group | `string` | n/a | yes |
| name | Workload name. Resources are named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| cidr\_block | CIDR of the VPC. It must be a /16 so the fixed subnet layout fits | `string` | `"10.0.0.0/16"` | no |
| environment | Deployment environment, for example integration or production | `string` | `""` | no |
| flow\_log\_retention\_days | Days to keep VPC flow logs | `number` | `365` | no |
| gateway\_endpoint\_services | Gateway endpoints to create, attached to the private and isolated route tables. Allowed: s3, dynamodb | `set(string)` | ```[ "s3" ]``` | no |
| interface\_endpoint\_services | Interface endpoints to create in the private subnets, by service name without the com.amazonaws.<region> prefix, for example ["ecr.api", "ecr.dkr", "logs", "secretsmanager"] | `set(string)` | `[]` | no |
| name\_suffix | Optional last part of the name, for example edge when one workload has several networks | `string` | `""` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| availability\_zones | Zones the subnets are in, in the order of the subnet ID lists |
| endpoints\_security\_group\_id | Security group of the interface endpoints |
| flow\_log\_group\_arn | Log group that receives the VPC flow logs |
| isolated\_route\_table\_id | Route table shared by the isolated subnets |
| isolated\_subnet\_ids | Subnets with no route out, for databases, one per zone |
| nat\_eips | Elastic IPs of the NAT gateways, one per zone; give these to partners that keep an allow-list |
| nat\_gateway\_ids | NAT gateway IDs, one per zone |
| private\_route\_table\_ids | Route tables of the private subnets, one per zone |
| private\_subnet\_ids | Private subnets with a route out through the NAT gateway of their zone, one per zone |
| public\_route\_table\_id | Route table shared by the public subnets |
| public\_subnet\_ids | Public subnets that hold the NAT gateways, one per zone |
| vpc\_cidr\_block | VPC CIDR block |
| vpc\_id | VPC ID |
<!-- END_TF_DOCS -->
