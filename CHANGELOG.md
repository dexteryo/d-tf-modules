# Changelog

All notable changes to this repository are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-23

### Added

- `modules/ecs-cluster`: ECS cluster with Container Insights, `FARGATE` and `FARGATE_SPOT` capacity providers, optional encrypted ECS Exec logging.
- `modules/ecs-service`: Fargate service with task definition, security group, ALB target group and listener rule, per-service log group, least-privilege execution and task roles, autoscaling, and Terraform ignoring task definition and desired count changes by default.
- `examples/ordering-agent`: two-container task (agent behind an ALB, MCP sidecar on loopback) with a customer-managed-KMS DynamoDB table.
- `terraform test` suites using `mock_provider "aws"`; they need no AWS credentials.
