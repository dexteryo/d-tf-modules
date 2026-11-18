# Development workflow

> Generated 2026-10-31 (INIT) from `v0.5.1`, `git log` and the CI workflow.

## The green gate

One command runs every check and is exactly what CI runs:

```bash
scripts/check.sh
```

It needs no AWS credentials (`README.md:69`). Steps, in order (`scripts/check.sh`):

| Step | Command |
| --- | --- |
| fmt | `terraform fmt -check -recursive` |
| validate | for every folder under `modules` and `examples` that holds a `.tf` file: `terraform init -backend=false -input=false` then `terraform validate -no-color` |
| test | for `modules/*` and `examples/ordering-agent`: `terraform init -backend=false -input=false` then `terraform test -no-color` |
| tflint | `tflint --init` then `tflint --recursive --config="$root/.tflint.hcl"` |
| trivy | `trivy config --ignorefile .trivyignore --severity HIGH,CRITICAL --exit-code 1 --skip-dirs '**/.terraform' .` |
| terraform-docs | for `modules/*`: `terraform-docs --config .terraform-docs.yml --output-check "$dir"` |
| identifiers | `scripts/check-no-foreign-identifiers.sh` then `tests/check-no-foreign-identifiers.test.sh` |
| shellcheck | `shellcheck scripts/*.sh tests/*.sh` |

The script runs under `set -euo pipefail`, so the first failing step stops it. `TF_PLUGIN_CACHE_DIR` defaults to a fresh `mktemp -d`, shared by every folder in the run.

Tools needed: `terraform` (tests need `>= 1.7`, CI uses 1.15.3), `tflint`, `trivy`, `terraform-docs`, `shellcheck`, `python3` (`README.md:31-33`).

### Local run on 2026-10-31

Command: `scripts/check.sh` from the repository root (macOS, Terraform 1.15.3 from the nix profile).

Result: exit 127 after 6 min 4 s. fmt, validate and every `terraform test` suite passed: the 16 committed modules (acm-certificate 20, alb 13, ci-oidc-role 18, cloudfront-spa 35, ecr 10, ecs-cluster 5, ecs-service 21, ecs-service-alarms 7, kms 6, rds-postgres 13, s3-bucket 10, security-group 7, sns-topic 6, tags 7, vpc 11, waf-web-acl 18) and `examples/ordering-agent` (2), so 209 runs and 0 failures. The script then stopped with `tflint: command not found`: `tflint`, `trivy`, `terraform-docs` and `shellcheck` are not installed on this machine. Run separately, `scripts/check-no-foreign-identifiers.sh` exited 0 and `tests/check-no-foreign-identifiers.test.sh` printed 12 `ok` lines and exited 0. TFLint, Trivy, the terraform-docs drift check and shellcheck were not verified locally; CI is where they run.

Caveat: during the run the working tree was on branch `feat/lambda-sqs-apigw` with uncommitted modules (`lambda`, `sqs-queue`, `apigw-http-lambda`) being added by another process. The script's `modules/*` glob picked those up too. The counts above are for the committed modules only.

## Single-module loop

```bash
cd modules/<name>
terraform init -backend=false -input=false
terraform validate
terraform test
terraform-docs --config ../../.terraform-docs.yml .   # regenerate the README block
```

Run `terraform-docs` from the repository root as `terraform-docs --config .terraform-docs.yml modules/<name>` to match what the check does; the config injects between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->`.

## Pre-commit hooks

`pre-commit install` (`README.md`, "Development"). Hooks (`.pre-commit-config.yaml`): `terraform_fmt`, `terraform_validate`, `terraform_tflint` (with the repo `.tflint.hcl`), `terraform_docs` (with `.terraform-docs.yml`) from `antonbabenko/pre-commit-terraform` `v1.96.2`; local hooks `no-foreign-identifiers` (always), `no-foreign-identifiers-test` (when `scripts/` or `tests/` change) and `shellcheck` on `scripts/` and `tests/` shell files. Pre-commit does not run `terraform test` or Trivy.

## CI

`.github/workflows/ci.yml`, workflow `CI`, on every `pull_request` and on `push` to `main`. One job `check` on `ubuntu-latest` with `permissions: contents: read`: checkout without persisted credentials, install Terraform 1.15.3 (wrapper off), TFLint, Trivy v0.76.1, terraform-docs v0.24.0 (SHA-256 verified), then `scripts/check.sh`. Every action is pinned by commit SHA.

## Branching

Observed in `git log` and `git branch -a`:

- `main` is the only long-lived branch.
- Work branches are `feat/<topic>` (for example `feat/acm-certificate`, `feat/ci-oidc-role-static-site`) and `fix/<topic>` (`fix/s3-bucket-input-validation`), merged by GitHub pull request with a merge commit ("Merge pull request #N from dexteryo/<branch>"). PRs #2 to #15 follow this; v0.1.0 to v0.2.1 were committed straight to `main`.
- Releases go through `release/vX.Y.Z` branches from v0.3.0 on (v0.3.0, v0.4.0, v0.5.0, v0.5.1), each a single `chore: release vX.Y.Z` commit. v0.3.1 was released inside its feature PR (#9).
- A remote `renovate/configure` branch exists; no Renovate config is on `main`.

Commit subjects use Conventional Commits with an optional module scope: `feat(ci-oidc-role): ...`, `fix(vpc): ...`, `docs: ...`, `chore: release v0.5.1`, `feat!:` for a breaking change (`5a123a3 feat!: require AWS provider ~> 6.0 in every module`).

## Release process

1. Each feature or fix commit adds its own CHANGELOG lines under `## [Unreleased]` (for example `7a48f1a`, `27d4768`, `4c15008`), using Keep a Changelog sections `Added`, `Changed`, `Removed`, and `Migration from vA.B.x` for breaking releases. Merge the PRs to `main`.
2. Open `release/vX.Y.Z` with one commit `chore: release vX.Y.Z` whose only change is renaming `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` (`git show 4fda7c7`).
3. Merge the release PR, then tag the merge commit `vX.Y.Z`. From v0.3.0 the tags are annotated and point at the merge commit (`git cat-file -t v0.5.1` → `tag`, target `6c52410`); v0.1.0 to v0.2.1 are lightweight tags on direct commits.

No release automation, tag workflow or GitHub release step exists in the repository; tagging is manual (Strongly Inferred: no workflow other than `ci.yml`, and no tag trigger in it).

## Adding a module

What every module added since v0.2.0 shipped with: the standard file set (`structure.md`), validation on inputs, a `tftest.hcl` suite with negative runs, `examples/basic/main.tf`, README sections plus the terraform-docs block, a row in the root `README.md` module table, and a CHANGELOG `Added` entry.
