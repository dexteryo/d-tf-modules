mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/ordering-integration-deploy"
    }
  }
}

variables {
  name              = "ordering"
  environment       = "integration"
  github_repository = "example-org/example-infra"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  tags              = { Environment = "integration" }

  ecr_repository_arns = ["arn:aws:ecr:eu-west-1:123456789012:repository/ordering-agent"]
  ecs_service_arns    = ["arn:aws:ecs:eu-west-1:123456789012:service/ordering-integration/ordering-integration"]
  pass_role_arns      = ["arn:aws:iam::123456789012:role/ordering-integration-execution", "arn:aws:iam::123456789012:role/ordering-integration-task"]
}

run "trust_is_scoped_to_the_repository_and_the_environment" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/example-infra:environment:integration"
    error_message = "The sub claim must name the repository and the environment."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The audience must be sts.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" && !can(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringLike)
    error_message = "Only web identity may assume the role and no pattern match is used."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The trust policy must name the given provider."
  }
}

run "github_environment_can_differ_from_the_environment_name" {
  command = apply

  variables {
    github_environment = "integration-eu"
  }

  assert {
    condition     = output.trust_subject == "repo:example-org/example-infra:environment:integration-eu"
    error_message = "github_environment must replace the default."
  }
}

run "immutable_ids_put_the_numeric_ids_in_the_subject" {
  command = apply

  variables {
    github_immutable_ids = { owner_id = 88313963, repository_id = 1425217396 }
  }

  assert {
    condition     = output.trust_subject == "repo:example-org@88313963/example-infra@1425217396:environment:integration"
    error_message = "The subject must carry the owner and repository IDs."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org@88313963/example-infra@1425217396:environment:integration"
    error_message = "The trust policy must match the immutable subject exactly."
  }
}

run "immutable_ids_must_be_positive_whole_numbers" {
  command = plan

  variables {
    github_immutable_ids = { owner_id = 0, repository_id = 1.5 }
  }

  expect_failures = [var.github_immutable_ids]
}

run "role_is_named_from_the_inputs" {
  command = apply

  assert {
    condition     = aws_iam_role.this.name == "ordering-integration-deploy"
    error_message = "The role is named <name>-<environment>-<name_suffix>."
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "Sessions last one hour by default."
  }
}

run "no_wildcard_resource_except_the_documented_ecr_and_ecs_exceptions" {
  command = apply

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement :
      !contains(s.Resource, "*") || contains(["EcrAuthorisationToken", "TaskDefinitions"], s.Sid)
    ])
    error_message = "Only ecr:GetAuthorizationToken and the task definition actions may use Resource *."
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Action if s.Sid == "EcrAuthorisationToken"][0] == ["ecr:GetAuthorizationToken"]
    error_message = "The ECR wildcard statement may hold the authorisation token action only."
  }

  assert {
    condition     = toset([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Action if s.Sid == "TaskDefinitions"][0]) == toset(["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"])
    error_message = "The ECS wildcard statement may hold the two task definition actions only."
  }

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : [for a in s.Action : !endswith(a, ":*")]
    ]))
    error_message = "No action may be a service wildcard."
  }
}

run "deploy_permissions_name_the_services_and_repositories" {
  command = apply

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "DeployServices"][0] == ["arn:aws:ecs:eu-west-1:123456789012:service/ordering-integration/ordering-integration"]
    error_message = "UpdateService must be limited to the listed services."
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "PushAndReadImages"][0] == ["arn:aws:ecr:eu-west-1:123456789012:repository/ordering-agent"]
    error_message = "Image push must be limited to the listed repositories."
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Condition.StringEquals["iam:PassedToService"] if s.Sid == "PassTaskRolesToEcs"][0] == "ecs-tasks.amazonaws.com"
    error_message = "PassRole must be limited to ECS tasks."
  }
}

run "static_site_permissions_name_the_buckets_keys_and_distributions" {
  command = apply

  variables {
    static_site_bucket_arns      = ["arn:aws:s3:::ordering-integration-web"]
    static_site_kms_key_arns     = ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
    cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE"]
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "ListStaticSiteBuckets"][0] == ["arn:aws:s3:::ordering-integration-web"] && [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Action if s.Sid == "ListStaticSiteBuckets"][0] == ["s3:ListBucket"]
    error_message = "Listing must be limited to the listed buckets."
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "WriteStaticSiteObjects"][0] == ["arn:aws:s3:::ordering-integration-web/*"]
    error_message = "Object writes must be limited to the objects of the listed buckets."
  }

  assert {
    condition     = toset([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Action if s.Sid == "WriteStaticSiteObjects"][0]) == toset(["s3:DeleteObject", "s3:PutObject"])
    error_message = "A sync needs only to upload and delete objects."
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "EncryptStaticSiteObjects"][0] == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"] && toset([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Action if s.Sid == "EncryptStaticSiteObjects"][0]) == toset(["kms:Decrypt", "kms:GenerateDataKey"])
    error_message = "Encryption must be limited to the listed keys and the two upload actions."
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "InvalidateDistributions"][0] == ["arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE"] && toset([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Action if s.Sid == "InvalidateDistributions"][0]) == toset(["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"])
    error_message = "Invalidations must be limited to the listed distributions."
  }
}

run "wildcard_static_site_resources_are_refused" {
  command = plan

  variables {
    static_site_bucket_arns      = ["arn:aws:s3:::*"]
    static_site_kms_key_arns     = ["arn:aws:kms:eu-west-1:123456789012:key/*"]
    cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/*"]
  }

  expect_failures = [var.static_site_bucket_arns, var.static_site_kms_key_arns, var.cloudfront_distribution_arns]
}

run "kms_alias_arn_is_refused" {
  command = plan

  variables {
    static_site_kms_key_arns = ["arn:aws:kms:eu-west-1:123456789012:alias/ordering-data"]
  }

  expect_failures = [var.static_site_kms_key_arns]
}

run "empty_kms_key_arn_is_refused" {
  command = plan

  variables {
    static_site_kms_key_arns = [""]
  }

  expect_failures = [var.static_site_kms_key_arns]
}

run "bare_distribution_id_is_refused" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["E2EXAMPLE"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "empty_distribution_arn_is_refused" {
  command = plan

  variables {
    cloudfront_distribution_arns = [""]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "statements_are_left_out_when_their_lists_are_empty" {
  command = apply

  variables {
    ecr_repository_arns = []
    ecs_service_arns    = []
    pass_role_arns      = []
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.deploy.policy).Statement) == 1
    error_message = "Without repositories, services or roles only the authorisation token statement remains."
  }
}

run "provider_can_be_created" {
  command = apply

  variables {
    create_oidc_provider = true
    oidc_provider_arn    = null
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com" && aws_iam_openid_connect_provider.github[0].client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The provider trusts GitHub with the sts.amazonaws.com audience."
  }
}

run "wildcard_repository_is_refused" {
  command = plan

  variables {
    github_repository = "example-org/*"
  }

  expect_failures = [var.github_repository]
}

run "wildcard_environment_is_refused" {
  command = plan

  variables {
    github_environment = "*"
  }

  expect_failures = [var.github_environment]
}

run "provider_arn_is_required_unless_one_is_created" {
  command = plan

  variables {
    oidc_provider_arn = null
  }

  expect_failures = [aws_iam_role.this]
}
