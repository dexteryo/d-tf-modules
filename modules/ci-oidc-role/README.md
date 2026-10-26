# ci-oidc-role

An IAM role that GitHub Actions assumes through OpenID Connect to build images and deploy one ECS service, to sync a static site into S3 and invalidate its CloudFront distribution, or both. The trust policy names a repository and an environment; there are no wildcards and no stored keys.

## Owns

- `aws_iam_role` named `<name>-<environment>-<name_suffix>` (suffix `deploy`) and its inline `deploy` policy.
- The trust policy: `sts:AssumeRoleWithWebIdentity` from the GitHub OIDC provider where `aud` is `sts.amazonaws.com` and `sub` is exactly `repo:<owner>/<name>:environment:<environment>`.
- Optionally the GitHub OIDC identity provider itself (`create_oidc_provider`).

## Does not own

- The ECR repositories, the ECS service, the task roles, the static site buckets, their KMS keys and the distributions; their ARNs are inputs.
- The deploy gate. Required reviewers on the GitHub environment decide who can run a job that carries the `environment:` claim.
- Terraform plan or apply roles. This role deploys container images and static site builds only.

## Usage

```hcl
module "deploy_role" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/ci-oidc-role?ref=v0.4.0"

  name              = "ordering"
  environment       = "integration"
  tags              = module.tags.all_tags
  github_repository = "example-org/example-app"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"

  ecr_repository_arns = [module.ecr.repository_arn]
  ecs_service_arns    = [module.service.service_arn]
  pass_role_arns      = [module.service.execution_role_arn, module.service.task_role_arn]

  static_site_bucket_arns      = [module.web_bucket.bucket_arn]
  static_site_kms_key_arns     = [module.kms.kms_key_arn]
  cloudfront_distribution_arns = [module.edge.distribution_arn]
}
```

Create one role per environment; pass `role_arn` as `role-to-assume` to the workflows in `d-github-actions`. An account has a single GitHub OIDC provider: create it once (`create_oidc_provider = true` in one call) and pass its ARN everywhere else.

## Permissions

| Sid | Actions | Resources |
| --- | --- | --- |
| `EcrAuthorisationToken` | `ecr:GetAuthorizationToken` | `*` (AWS has no resource-level permission for it) |
| `PushAndReadImages` | layer upload actions, `ecr:PutImage`, `ecr:BatchGetImage`, `ecr:DescribeImages`, `ecr:GetDownloadUrlForLayer` | `ecr_repository_arns` |
| `TaskDefinitions` | `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition` | `*` (AWS has no resource-level permission for them) |
| `DeployServices` | `ecs:DescribeServices`, `ecs:UpdateService` | `ecs_service_arns` |
| `PassTaskRolesToEcs` | `iam:PassRole` | `pass_role_arns`, only to `ecs-tasks.amazonaws.com` |
| `ListStaticSiteBuckets` | `s3:ListBucket` | `static_site_bucket_arns` |
| `WriteStaticSiteObjects` | `s3:PutObject`, `s3:DeleteObject` | the objects of `static_site_bucket_arns` (`<arn>/*`) |
| `EncryptStaticSiteObjects` | `kms:GenerateDataKey`, `kms:Decrypt` | `static_site_kms_key_arns` |
| `InvalidateDistributions` | `cloudfront:CreateInvalidation`, `cloudfront:GetInvalidation` | `cloudfront_distribution_arns` |

The statements after the first are omitted when their input list is empty. The two wildcard statements are the only documented exceptions.

## Left out of the reference shape

The reference module creates a family of roles per account type (branch and protected-branch roles, Terraform state, DNS, lambda, artefact registry, ticketing and read-only attachments), matches repositories by wildcard path patterns and branch or tag, and reads an account alias map. GitHub's environment claim replaces the branch distinction, one role per environment replaces the account type switch, and every repository is named in full.

## Tests

`terraform test` with `mock_provider "aws"` covers the trust scoping (repository, environment, audience, no pattern match), the GitHub environment override, naming, the wildcard allow-list, service and repository scoping, the `PassRole` condition, static site bucket, key and distribution scoping, omitted statements, creating the provider and the input validations, including wildcard bucket, key and distribution ARNs.

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
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment the role belongs to. It is also the default GitHub environment the trust policy accepts | `string` | n/a | yes |
| github\_repository | Repository allowed to assume the role, as owner/name. Wildcards are refused | `string` | n/a | yes |
| name | Workload name. The role is named <name>-<environment>-<name\_suffix> | `string` | n/a | yes |
| cloudfront\_distribution\_arns | CloudFront distributions the role may invalidate after a sync | `list(string)` | `[]` | no |
| create\_oidc\_provider | Create the GitHub OIDC identity provider. An account has one, so enable this in a single role module only | `bool` | `false` | no |
| ecr\_repository\_arns | ECR repositories the role may push images to and read from | `list(string)` | `[]` | no |
| ecs\_service\_arns | ECS services the role may update and describe. Registering task definitions is allowed whenever this list is not empty | `list(string)` | `[]` | no |
| github\_environment | GitHub environment whose jobs may assume the role. Defaults to the environment variable. Protection rules on that GitHub environment are the deploy gate | `string` | `null` | no |
| max\_session\_duration | Seconds a session of the role lasts (3600 to 43200) | `number` | `3600` | no |
| name\_suffix | Last part of the role name | `string` | `"deploy"` | no |
| oidc\_provider\_arn | ARN of the GitHub OIDC identity provider of the account, arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com. Required unless create\_oidc\_provider is true | `string` | `null` | no |
| pass\_role\_arns | Task and execution role ARNs the role may hand to ECS. Only ecs-tasks.amazonaws.com may receive them | `list(string)` | `[]` | no |
| permissions\_boundary\_arn | Permissions boundary policy attached to the role | `string` | `null` | no |
| static\_site\_bucket\_arns | S3 buckets the role may sync a static site build into: list the bucket, upload and delete objects | `list(string)` | `[]` | no |
| static\_site\_kms\_key\_arns | KMS keys encrypting those buckets; the role may generate data keys and decrypt with them, which SSE-KMS uploads need | `list(string)` | `[]` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| oidc\_provider\_arn | ARN of the GitHub OIDC identity provider the role trusts |
| role\_arn | ARN of the role; pass it as role-to-assume to the workflows of d-github-actions |
| role\_name | Name of the role |
| trust\_subject | The sub claim the role accepts, repo:<owner>/<name>:environment:<environment> |
<!-- END_TF_DOCS -->