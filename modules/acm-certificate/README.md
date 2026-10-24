# acm-certificate

One public ACM certificate, validated by DNS in a Route 53 hosted zone you already have. The apply waits until ACM has issued it, so `certificate_arn` can go straight into a CloudFront distribution or an ALB listener in the same apply.

## Owns

- The `aws_acm_certificate` for `domain_name` and `subject_alternative_names`, validated by DNS, with `create_before_destroy` so a replacement is issued before the old certificate is detached.
- One validation CNAME per distinct name in the hosted zone. A name and its wildcard (`example.com` and `*.example.com`) share one CNAME, so they share one record.
- The `aws_acm_certificate_validation` that waits for issuance, for at most `validation_timeout`.

## Does not own

- The hosted zone. It is not looked up and not created. Pass its ID as `hosted_zone_id`.
- The domain registration or the delegation of the domain to Route 53.
- Whatever uses the certificate. Pass `certificate_arn` to `modules/alb` or `modules/cloudfront-spa`.
- Private certificates, email validation and imported certificates.

## Provider and region

The certificate is created in the region of the provider you pass. CloudFront only accepts certificates from `us-east-1`; a load balancer needs one in its own region. Choose the region with `providers`:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

The module declares no `configuration_aliases`; pass `providers = { aws = aws.us_east_1 }` as in the usage below. Without `providers`, the default provider is used.

## Usage

```hcl
module "edge_certificate" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/acm-certificate?ref=v0.4.0"

  providers = { aws = aws.us_east_1 }

  name                      = "ordering"
  environment               = "production"
  domain_name               = "example.com"
  subject_alternative_names = ["*.example.com"]
  hosted_zone_id            = "Z0123456789ABCDEFGHIJ"
  tags                      = module.tags.all_tags
}
```

## Before you apply

- The zone must already exist and be authoritative for the domain, either because the domain is registered in Route 53 or because it is delegated to the zone's name servers. Otherwise ACM never sees the validation records and the apply waits for `validation_timeout` and then fails.
- All names on the certificate must live in that one zone.
- ACM public certificates are free.
- Renewal is automatic for as long as the validation records stay in the zone. Do not remove them by hand.

## Defaults worth knowing

- The key algorithm is `RSA_2048`. `EC_prime256v1` and `EC_secp384r1` are the other choices.
- The validation timeout is 30 minutes.
- `domain_name` and each subject alternative name must be lower-case DNS names of at least two labels, with no trailing dot. Only a leading `*.` wildcard is allowed. `domain_name` may itself be a wildcard.
- Subject alternative names must not repeat each other or `domain_name`. The repeat of `domain_name` is checked by a precondition on the certificate, so it fails at plan time with a message naming the input; a variable validation cannot read another variable on Terraform before 1.9.
- Validation records have a TTL of 60 seconds and `allow_overwrite = true`, so a record left behind by an earlier certificate is taken over.
- The validation records are keyed by the names you pass, not by the values ACM returns, so their addresses are known at plan time.

## Left out on purpose

Certificate transparency opt-out, email validation, private CAs, importing certificates, a zone per name and looking up the zone by name. Each makes the module larger for callers that do not need it.

## Tests

`terraform test` with `mock_provider "aws"` covers the Name tag with and without a suffix and environment, the defaults, one name giving one record, apex plus wildcard giving one record, several distinct names giving one record each, the validated ARN output, the key algorithm and timeout being passed through, and every input validation. The mocked certificate returns its validation options through `override_resource`; the two runs that return several options use their own `state_key` so that an earlier run cannot hide the override. The mock cannot show that ACM really returns one CNAME for a name and its wildcard; that is ACM's documented behaviour and is the reason the records are keyed by the name with `*.` removed.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials: a certificate for `example.com` and `*.example.com` for a load balancer, and one in `us-east-1` for CloudFront.

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
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain\_name | Primary name of the certificate, lower case without a trailing dot. A wildcard such as *.example.com is allowed | `string` | n/a | yes |
| hosted\_zone\_id | Public Route 53 hosted zone that holds every name on the certificate. It must already exist and be authoritative for the domain | `string` | n/a | yes |
| name | Workload name. The Name tag is <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| environment | Deployment environment, for example integration or production | `string` | `""` | no |
| key\_algorithm | Key algorithm of the certificate: RSA\_2048, EC\_prime256v1 or EC\_secp384r1 | `string` | `"RSA_2048"` | no |
| name\_suffix | Optional last part of the name, for example edge when one workload has several certificates | `string` | `""` | no |
| subject\_alternative\_names | Extra names on the certificate, for example ["*.example.com"] or ["ops.example.com"]. Must not repeat each other or domain\_name | `list(string)` | `[]` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| validation\_timeout | How long to wait for ACM to issue the certificate, for example 30m. Terraform fails the apply when it is exceeded | `string` | `"30m"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| certificate\_arn | ARN of the certificate. Only known once ACM has issued it, so a listener or distribution that uses it waits for validation |
| domain\_name | Primary name of the certificate |
| validation\_record\_fqdns | Names of the DNS validation records in the hosted zone. Keep them: ACM renews the certificate through them |
<!-- END_TF_DOCS -->
