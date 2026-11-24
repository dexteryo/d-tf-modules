# ssm-egress-proxy

A private HTTPS proxy on one Graviton instance. Its traffic leaves through the subnet's NAT gateway, and the only way in is an SSM port-forwarding session. Use it when a partner allowlists your VPC's NAT IPs and people need to reach that partner from laptops whose IPs change: the API with curl or an HTTP client, the partner's documentation with a browser.

## Owns

- `aws_instance` named `<name>-<environment>-<name_suffix>` (suffix `egress-proxy` by default), Amazon Linux 2023 arm64, `t4g.micro` by default, without a public IP.
- squid, installed at boot, listening on `127.0.0.1:<proxy_port>` (3128 by default). It accepts only `CONNECT` to port 443, so it tunnels HTTPS without reading it, caches nothing and drops `Via` and `X-Forwarded-For`. With `allowed_domains` it refuses every other destination.
- A security group with no ingress rule and one HTTPS egress rule per range in `egress_ipv4_cidrs`.
- An instance role with `AmazonSSMManagedInstanceCore`, and its instance profile.

## Does not own

- The VPC, the subnet and the NAT gateway (`vpc`). The subnet's NAT gateway decides the source IP partners see, so give the partner that gateway's Elastic IP.
- The KMS key (`kms`). Its key policy must let IAM policies in the account use it, which the `kms` module does by default, or EC2 cannot launch the instance with an encrypted root volume.
- Who may open a session. Grant `ssm:StartSession` on the instance and the `AWS-StartPortForwardingSession` document through IAM; requiring MFA there is what keeps the proxy private.
- Session logging. Attach a policy to `role_name` and set up Session Manager preferences if you need an audit trail beyond CloudTrail's `StartSession` events.

## Usage

```hcl
module "egress_proxy" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/ssm-egress-proxy?ref=v0.9.1"

  name            = "ordering"
  environment     = "integration"
  tags            = module.tags.all_tags
  vpc_id          = module.vpc.vpc_id
  subnet_id       = module.vpc.private_subnet_ids[0]
  kms_key_arn       = module.data_key.kms_key_arn
  egress_ipv4_cidrs = ["0.0.0.0/0"]
  allowed_domains   = [".example.com"]
}
```

Then, with the Session Manager plugin installed, open the tunnel with the `port_forward_command` output and point a client at it:

```sh
aws ssm start-session --target <instance_id> --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=3128,localPortNumber=3128
HTTPS_PROXY=http://127.0.0.1:3128 curl https://api.example.com/health
open -na "Google Chrome" --args --user-data-dir="$HOME/.chrome-proxy" --proxy-server=http://127.0.0.1:3128
```

## Defaults worth knowing

- Egress has no default. `egress_ipv4_cidrs` must let the instance reach Systems Manager and the package repositories as well as the proxied hosts. Partners behind a CDN or Azure Front Door have no fixed ranges, so in practice it is `["0.0.0.0/0"]`, and that exception then sits visibly in the calling configuration, where a scanner can flag it. A VPC with `ssm`, `ssmmessages` and `ec2messages` interface endpoints lets you narrow it to the partners' ranges, but `dnf upgrade` at boot then needs a route to the Amazon Linux repositories too.

- `t4g.micro` (1 GiB) is the smallest type that works. On a `t4g.nano` (512 MiB) the `dnf upgrade` at boot runs out of memory, the SSM agent stops answering, and sessions hang at Connecting.
- Any destination is allowed until you set `allowed_domains`. A browser reading a partner's documentation also loads fonts and scripts from other hosts, so an allowlist that is too tight breaks those pages.
- The AMI is read once. A new Amazon Linux release does not replace the instance; it runs `dnf upgrade` at every boot. To move to a new AMI, apply with `-replace` on `aws_instance.this`.
- Changing `proxy_port` or `allowed_domains` changes the user data and replaces the instance.

## Left out on purpose

- Plain HTTP, other ports and caching. The proxy exists to give a fixed source IP to HTTPS calls, nothing else.
- High availability. One instance in one zone is enough for people testing by hand; the application should call partners directly through the NAT gateways.
- Inbound access of any kind: no SSH key, no public IP, no ingress rule.

## Tests

`terraform test` with `mock_provider "aws"` covers naming and tags, the private, IMDSv2-only, encrypted instance, the SSM-only role, HTTPS-only egress to the given ranges, the port-forward command, the squid configuration with and without `allowed_domains`, and the instance type, port, domain and egress validations.

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
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_ssm_parameter.ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| egress\_ipv4\_cidrs | IPv4 ranges the instance may reach on HTTPS. Systems Manager must be among them, either the internet (0.0.0.0/0) or a VPC with ssm, ssmmessages and ec2messages interface endpoints, and so must the package repositories the instance updates from at boot | `list(string)` | n/a | yes |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| kms\_key\_arn | Customer-managed key that encrypts the root volume. Its key policy must let IAM policies in this account use it, or EC2 cannot launch the instance | `string` | n/a | yes |
| name | Workload name. Resources are named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| subnet\_id | Private subnet for the instance. Its route to the internet (a NAT gateway) decides the source IP partners see | `string` | n/a | yes |
| vpc\_id | VPC the proxy runs in | `string` | n/a | yes |
| allowed\_domains | Destinations the proxy may tunnel to, in squid dstdomain form (a leading dot matches subdomains, for example .example.com). Empty allows any host | `list(string)` | `[]` | no |
| ami\_ssm\_parameter | Public SSM parameter that holds the Amazon Linux 2023 arm64 AMI ID | `string` | `"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"` | no |
| instance\_type | Graviton instance type; the AMI is arm64. It needs at least 1 GiB of memory, because dnf upgrade at boot runs a t4g.nano (512 MiB) out of memory and stalls the SSM agent | `string` | `"t4g.micro"` | no |
| name\_suffix | Optional last part of the name | `string` | `"egress-proxy"` | no |
| proxy\_port | Port squid listens on, on the instance's loopback only | `number` | `3128` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instance\_id | Target of aws ssm start-session |
| port\_forward\_command | AWS CLI command that opens the proxy on localhost:<proxy\_port> |
| proxy\_port | Port squid listens on, on the instance's loopback |
| role\_name | Instance role, for attaching extra policies such as session logging |
| security\_group\_id | Security group of the instance; it has no ingress rule |
<!-- END_TF_DOCS -->
