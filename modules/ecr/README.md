# ecr

One ECR repository: immutable tags, scan on push, KMS encryption, a lifecycle policy and an optional pull policy for other accounts.

## Owns

- `aws_ecr_repository`, its lifecycle policy and, when `pull_account_ids` is set, a repository policy that lets those accounts pull.
- Optionally the key that encrypts the images, created through `../kms` when `create_kms_key` is true (the default).

## Does not own

- The images. Builds push digests with `d-github-actions`; the deploy role of `ci-oidc-role` is the only push permission.
- The environment. One repository serves every environment because the same digest is promoted from one environment to the next; the module therefore takes no `environment`.

## Usage

```hcl
module "ecr" {
  for_each = toset(["ordering-agent", "ordering-mcp"])
  source   = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/ecr?ref=v0.2.0"

  name           = each.key
  create_kms_key = false
  kms_key_arn    = module.app_key.kms_key_arn
  tags           = module.tags.all_tags
}
```

`create_kms_key` is a plain boolean on purpose: Terraform must know at plan time whether to create the key, and an ARN produced by another resource is unknown until apply.

## Defaults worth knowing

- Tags are immutable (`mutable_image_tags = false`) so a digest and its tag cannot drift.
- Untagged images expire after 7 days and the newest 30 tagged images are kept; `enable_lifecycle_policy = false` turns the policy off.
- Only this account may pull unless `pull_account_ids` lists others, and those accounts only get pull actions.

## Left out of the reference shape

The reference module can share a repository with every account of an organisation or of a team, hard-codes organisation ids and takes the environment as a name suffix. Those options are specific to a multi-account estate and are not carried over; list account ids explicitly instead. Its test-only force-delete flag is kept as `force_delete`, with a safer default.

## Tests

`terraform test` with `mock_provider "aws"` covers immutability, scanning, encryption, own or given key, namespace, lifecycle rules, the pull policy and account id validation.

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

| Name | Source | Version |
| ---- | ------ | ------- |
| kms | ../kms | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository_policy.pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Repository name, for example ordering-agent | `string` | n/a | yes |
| create\_kms\_key | Create a key for the images through the kms module. Set false and pass kms\_key\_arn to use a key you own; the choice cannot depend on a value known only after apply | `bool` | `true` | no |
| enable\_lifecycle\_policy | Expire old images according to untagged\_expiry\_days and max\_tagged\_images | `bool` | `true` | no |
| force\_delete | Delete the repository even when it still holds images. Only for throwaway repositories | `bool` | `false` | no |
| kms\_key\_arn | Customer-managed key that encrypts the images when create\_kms\_key is false | `string` | `null` | no |
| max\_tagged\_images | Number of tagged images to keep; older ones expire | `number` | `30` | no |
| mutable\_image\_tags | Allow a tag to be pushed again. Keep false: deploys reference digests and every build gets its own tag | `bool` | `false` | no |
| namespace | Optional path in front of the name, for example example-org. The repository is <namespace>/<name> | `string` | `""` | no |
| pull\_account\_ids | AWS account ids, besides this one, whose roles may pull the images. Empty creates no repository policy | `list(string)` | `[]` | no |
| scan\_on\_push | Run the ECR image scan on every push | `bool` | `true` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| untagged\_expiry\_days | Days an untagged image is kept after it was pushed | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| kms\_key\_arn | Key that encrypts the images, given or created |
| registry\_id | Account id of the registry |
| repository\_arn | ARN of the repository |
| repository\_name | Name of the repository including the namespace |
| repository\_url | URL of the repository, <registry>/<name> |
<!-- END_TF_DOCS -->