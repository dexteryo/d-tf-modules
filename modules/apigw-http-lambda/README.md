# apigw-http-lambda

One regional HTTP API that sends a fixed list of routes to one Lambda function, with throttling and encrypted access logs.

## Owns

- `aws_apigatewayv2_api` (HTTP) named `<name>-<environment>[-<name_suffix>]`, one `AWS_PROXY` integration with the version 2.0 payload, and one route per entry of `routes`.
- One invoke permission per route, naming the method and path, so API Gateway can reach the function only through the routes you listed.
- The `$default` stage with auto deploy, throttling on the stage and on every route, and access logs in a log group encrypted with `logs_kms_key_arn`. The access log format has request IDs, route, status and latencies; it never records request bodies or headers.

## Does not own

- The function (`lambda`). Pass its `function_name` and `invoke_arn`.
- Authorisation. The routes have no authoriser, so the function must verify every caller itself, for example by checking a signature before it reads the body. Do not use this module for an endpoint that needs IAM or JWT checks.
- Custom domains, certificates and WAF. The API answers on its `execute-api` URL.
- The logs KMS key (`kms`). Its policy must let the CloudWatch Logs service use it for the access log group.

## Usage

```hcl
module "webhooks" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/apigw-http-lambda?ref=v0.6.0"

  name                = "ordering"
  environment         = "integration"
  name_suffix         = "webhooks"
  tags                = module.tags.all_tags
  function_name       = module.intake.function_name
  function_invoke_arn = module.intake.invoke_arn
  routes              = ["POST /webhooks/acme", "POST /webhooks/globex"]
  logs_kms_key_arn    = module.logs_key.kms_key_arn
}
```

Routes are exact. Wildcards and path parameters such as `{partner}` are refused, so every caller you allow is visible in the plan. The stage and route limits are per route, not per caller.

## Tests

`terraform test` with `mock_provider "aws"` covers one route per key, the integration, the per-route invoke permissions and their statement ids, throttling on the stage and on each route, the encrypted access log group and its format, and the route and timeout validation.

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
| aws | 6.71.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_apigatewayv2_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_integration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_route.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_stage.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [aws_cloudwatch_log_group.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_lambda_permission.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| function\_invoke\_arn | Invoke ARN of that function, the invoke\_arn output of the lambda module | `string` | n/a | yes |
| function\_name | Name of the Lambda function every route calls, the function\_name output of the lambda module | `string` | n/a | yes |
| logs\_kms\_key\_arn | Customer-managed key that encrypts the access log group. Its key policy must let the CloudWatch Logs service use it | `string` | n/a | yes |
| name | Workload name. The API is named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| routes | Route keys the API accepts, each METHOD /path with no wildcard or path parameter, for example POST /webhooks/acme. Each gets its own invoke permission, so nothing else can reach the function through this API | `list(string)` | n/a | yes |
| integration\_timeout\_ms | How long API Gateway waits for the function. The HTTP API maximum is 30000 | `number` | `5000` | no |
| log\_retention\_days | Days the access logs are kept | `number` | `365` | no |
| name\_suffix | Optional last part of the name, for example webhooks | `string` | `null` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| throttling\_burst\_limit | Burst requests, applied to the stage and to every route | `number` | `50` | no |
| throttling\_rate\_limit | Steady requests per second, applied to the stage and to every route | `number` | `25` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| access\_log\_group\_name | Name of the access log group |
| api\_id | ID of the HTTP API |
| execution\_arn | Execution ARN of the HTTP API, for further invoke permissions |
| invoke\_url | Base URL of the API; append a route path |
<!-- END_TF_DOCS -->
