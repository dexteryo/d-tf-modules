# kms

One customer-managed KMS key with an alias, rotation always on and a key policy built from small, named inputs.

## Owns

- `aws_kms_key` and `aws_kms_alias`, named `alias/<name>-<environment>[-<name_suffix>]`.
- The key policy: the account root, optional management, encrypt and decrypt principals, grants to AWS services and any extra statements.

## Does not own

- Who may use the key through IAM identity policies. With the default `enable_iam_policy_delegation = true` the account root enables IAM policies, so the roles that need the key (for example the execution role of `ecs-service`) grant themselves access by naming the key ARN. Switch it off and list principals explicitly when you want the key policy to be the only gate; then create the roles first, because a key policy cannot name a role that does not exist.
- Anything that is encrypted with the key. ECR, SNS, DynamoDB and log groups take the ARN.

## Usage

```hcl
module "app_key" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/kms?ref=v0.2.0"

  name        = "ordering"
  environment = "integration"
  name_suffix = "app"
  description = "Ordering integration: images, secrets and task logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.eu-west-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/ordering-integration"]
    }
  }]
}
```

## Defaults worth knowing

- Rotation is always on; there is no input to turn it off.
- The deletion window is 30 days, the longest AWS allows.
- Management principals can administer the key but not use it. Encrypt principals can encrypt, decrypt and generate data keys. Decrypt principals can only decrypt.
- Key policies use `Resource = "*"` because in a key policy the resource is the key itself.

## Left out of the reference shape

The reference module is built on the policy-document data source, has an "override the whole policy" input and a default administrator list tied to one organisation, and supports a deny-all-others pattern per principal. This module builds the policy with `jsonencode` so tests can assert on it, offers `additional_statements` instead of replacing the whole policy, and has no organisation defaults.

## Tests

`terraform test` with `mock_provider "aws"` covers rotation, naming, tags, the root statement with and without delegation, principal statements, conditional service grants, extra statements and the deletion window bounds.

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
| aws | 5.100.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| description | What the key encrypts | `string` | n/a | yes |
| name | Workload name. The alias is alias/<name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| additional\_statements | Extra key policy statements, as objects in IAM JSON policy shape | `any` | `[]` | no |
| decrypt\_principals | Principal ARNs that may only decrypt | `list(string)` | `[]` | no |
| deletion\_window\_in\_days | Days AWS waits before deleting the key after it is scheduled for deletion (7 to 30) | `number` | `30` | no |
| enable\_iam\_policy\_delegation | Let IAM identity policies in this account grant use of the key (root principal gets kms:*). Turn it off to restrict use to the principals listed below | `bool` | `true` | no |
| encrypt\_principals | Principal ARNs that may encrypt, decrypt and generate data keys | `list(string)` | `[]` | no |
| environment | Deployment environment (for example integration, staging, production). Leave empty for keys shared by all environments | `string` | `""` | no |
| management\_principals | Principal ARNs that may administer the key but not use it. The account root administers the key when enable\_iam\_policy\_delegation is off | `list(string)` | `[]` | no |
| name\_suffix | Optional last part of the alias, for example app or tokens when one workload has several keys | `string` | `""` | no |
| service\_grants | AWS services that may use the key. actions defaults to encrypt, decrypt and generate data key. condition narrows the grant, for example to one log group | ```list(object({ sid = string service = string actions = optional(list(string), ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]) condition = optional(object({ test = string variable = string values = list(string) })) }))``` | `[]` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| key\_rotation\_enabled | Whether automatic key rotation is on; always true |
| kms\_alias\_arn | ARN of the alias |
| kms\_alias\_name | Alias of the key, alias/<name>-<environment>[-<name\_suffix>] |
| kms\_key\_arn | ARN of the key |
| kms\_key\_id | ID of the key |
<!-- END_TF_DOCS -->