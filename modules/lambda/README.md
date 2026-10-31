# lambda

One Lambda function with its execution role, an encrypted log group and, when you give it subnets, VPC access. The code is shipped by a deploy workflow after the first apply; Terraform ignores it from then on.

## Owns

- `aws_lambda_function` named `<name>-<environment>[-<name_suffix>]`: arm64 by default, JSON logs, environment variables encrypted with `kms_key_arn`.
- A log group `/aws/lambda/<function name>`, encrypted with `logs_kms_key_arn` and kept for a year by default.
- An execution role named `<function name>-lambda`, holding only log writing on its own log group, `kms:Decrypt` on `kms_key_arn`, the `policy_statements` you pass, and in a VPC the managed network interface policy.
- A placeholder zip for the first apply (Node.js, answers 503), named after the handler's file so the handler resolves. `filename` replaces it. Terraform ignores `filename` and `source_code_hash` afterwards, so a deploy never shows as drift.

## Does not own

- The KMS keys (`kms`). The logs key policy must let the CloudWatch Logs service use it for this log group.
- Anything that calls the function: API Gateway routes (`apigw-http-lambda`), event source mappings and permissions.
- Packaging and deploying the code. `d-github-actions` has `actions/lambda-deploy`, which updates the code by `function_name`.
- Secret values. Pass a secret's ARN in `environment_variables` and read it at run time; the role needs `secretsmanager:GetSecretValue` on it through `policy_statements`.
- Reserved concurrency, X-Ray, code signing and a function-level dead-letter queue. Add them in the caller if you need them.

## Usage

```hcl
module "intake" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/lambda?ref=v0.6.0"

  name             = "ordering"
  environment      = "integration"
  name_suffix      = "intake"
  tags             = module.tags.all_tags
  runtime          = "nodejs22.x"
  handler          = "intake.handler"
  kms_key_arn      = module.data_key.kms_key_arn
  logs_kms_key_arn = module.logs_key.kms_key_arn

  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.worker_security_group.security_group_id]

  policy_statements = [{
    sid       = "SendToQueue"
    actions   = ["sqs:SendMessage"]
    resources = [module.jobs.queue_arn]
  }]
}
```

## Tests

`terraform test` with `mock_provider "aws"` covers naming, encryption, JSON logs, the placeholder, running with and without a VPC, the subnet and security group validation, the statements on the role (no wildcard resources) and the architecture validation.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| archive | ~> 2.0 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| archive | 2.8.1 |
| aws | 6.71.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.vpc_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [archive_file.placeholder](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| handler | Handler, <file>.<export>, for example index.handler | `string` | n/a | yes |
| kms\_key\_arn | Customer-managed key that encrypts the environment variables. The role gets kms:Decrypt on it | `string` | n/a | yes |
| logs\_kms\_key\_arn | Customer-managed key that encrypts the log group. Its key policy must let the CloudWatch Logs service use it | `string` | n/a | yes |
| name | Workload name. The function is named <name>-<environment>[-<name\_suffix>] and its role adds -lambda | `string` | n/a | yes |
| runtime | Lambda runtime, for example nodejs22.x | `string` | n/a | yes |
| architectures | Instruction set of the function | `list(string)` | ```[ "arm64" ]``` | no |
| environment\_variables | Environment variables. Never put a secret value here; pass the ARN of a secret and read it at run time | `map(string)` | `{}` | no |
| filename | Zip with the code for the first apply. Null uses a placeholder that answers 503 until the deploy workflow ships the real code; the code is ignored after creation | `string` | `null` | no |
| log\_retention\_days | Days the function's logs are kept | `number` | `365` | no |
| memory\_size | Memory in MB | `number` | `256` | no |
| name\_suffix | Optional last part of the name, for example webhook-intake | `string` | `null` | no |
| policy\_statements | Extra permissions for the function's role, one object per statement. Name resources exactly; the module adds only log writing, kms:Decrypt on kms\_key\_arn and, in a VPC, the network interface actions | ```list(object({ sid = string actions = list(string) resources = list(string) }))``` | `[]` | no |
| security\_group\_ids | Security groups for the function when it runs in a VPC | `list(string)` | `[]` | no |
| subnet\_ids | Subnets for the function. Empty runs it outside a VPC; set both subnet\_ids and security\_group\_ids to attach it | `list(string)` | `[]` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| timeout | Function timeout in seconds | `number` | `10` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| function\_arn | ARN of the function |
| function\_name | Name of the function; the deploy workflow updates its code by this name |
| invoke\_arn | Invoke ARN, the integration target for the apigw-http-lambda module |
| log\_group\_arn | ARN of the function's log group |
| log\_group\_name | Name of the function's log group |
| role\_arn | ARN of the function's execution role |
| role\_name | Name of the function's execution role, for attaching further policies |
<!-- END_TF_DOCS -->
