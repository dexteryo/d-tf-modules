# s3-bucket

One private S3 bucket: KMS-encrypted, versioned, Block Public Access on, ACLs disabled, TLS required, with optional Object Lock in compliance mode and optional read access for one CloudFront distribution through origin access control.

## Owns

- `aws_s3_bucket` and its versioning, encryption, public access block, ownership controls and lifecycle configuration.
- The bucket policy: a deny for requests that do not use TLS, plus one `s3:GetObject` statement for a CloudFront distribution when `cloudfront_distribution_arn` is set.
- Object Lock default retention when `object_lock_retention_days` is set.

## Does not own

- The KMS key. Create it with `modules/kms` and pass `kms_key_arn`. When CloudFront reads the bucket the key policy must also let `cloudfront.amazonaws.com` decrypt, with `aws:SourceArn` set to the distribution; use `service_grants` on the key.
- The CloudFront distribution or its origin access control. The distribution takes `bucket_regional_domain_name` and this module takes the distribution's ARN; Terraform resolves that at resource level, because only the bucket policy waits for the distribution.
- Who may read or write objects through IAM. Grant that on the identity side, naming `bucket_arn` and the key.

## Usage

```hcl
module "documents" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/s3-bucket?ref=v0.5.0"

  name                       = "ordering"
  environment                = "production"
  name_suffix                = "documents"
  kms_key_arn                = module.documents_key.kms_key_arn
  object_lock_retention_days = 365
  tags                       = module.tags.all_tags
}
```

This creates a bucket named `ordering-production-documents-<account id>`.

## Defaults worth knowing

- The account ID is appended to the name because bucket names are global. Set `append_account_id = false` to drop it.
- Versioning is always on. Without Object Lock, superseded versions expire after `noncurrent_version_expiration_days` (90). With Object Lock they cannot be removed, so that rule is left out.
- Object Lock is compliance mode only. Nobody, including the account root, can shorten or remove a retention, and a locked bucket cannot be emptied until the retention ends. Keep it at 1 day outside production.
- Unfinished multipart uploads are aborted after 7 days.
- There is no `force_destroy` input; empty the bucket before destroying it.

## Left out on purpose

Server access logging, replication, event notifications and CORS. Each depends on a second bucket, a second region or a consumer, and adding them here would make every caller carry them. Trivy's logging finding is below the `HIGH` threshold the repository gates on.

## Tests

`terraform test` with `mock_provider "aws"` covers the name, tags, Block Public Access, encryption with the given key, versioning, the TLS-only policy, the CloudFront statement, Object Lock with and without retention, the lifecycle rule and input validation.

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
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| kms\_key\_arn | Customer-managed key that encrypts the objects | `string` | n/a | yes |
| name | Workload name. The bucket is named <name>-<environment>[-<name\_suffix>][-<account id>] | `string` | n/a | yes |
| abort\_incomplete\_multipart\_upload\_days | Days after which an unfinished multipart upload is aborted | `number` | `7` | no |
| append\_account\_id | Append the account ID to the name. Bucket names are global, so this keeps the same module call valid in every account | `bool` | `true` | no |
| cloudfront\_distribution\_arn | Distribution allowed to read objects through origin access control. Null for buckets CloudFront never serves | `string` | `null` | no |
| environment | Deployment environment, for example integration or production. Leave empty for a bucket shared by all environments | `string` | `""` | no |
| name\_suffix | Optional last part of the name, for example documents or uploads when one workload has several buckets | `string` | `""` | no |
| noncurrent\_version\_expiration\_days | Days before superseded object versions expire. Ignored while Object Lock is on, because locked versions cannot be removed | `number` | `90` | no |
| object\_lock\_retention\_days | Compliance-mode Object Lock default retention in days. Null leaves Object Lock off. Compliance mode cannot be shortened or removed by anyone, including the account root, so keep it short outside production | `number` | `null` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | Bucket ARN |
| bucket\_id | Bucket name |
| bucket\_regional\_domain\_name | Regional domain name a CloudFront distribution uses as the origin |
<!-- END_TF_DOCS -->
