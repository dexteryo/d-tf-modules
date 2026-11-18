# Instructions for AI agents

> Generated 2026-10-31 (INIT) from `v0.5.1`. Read `structure.md` and `coding-standards.md` before changing a module; read `security.md` before changing any IAM, network or encryption default.

## Before you start

1. Check the branch and the working tree (`git status`). Other agents run in this repository (ralph loops leave state in `.clever/ralph/`; on 2026-10-31 the tree held uncommitted `lambda`, `sqs-queue` and `apigw-http-lambda` modules on `feat/lambda-sqs-apigw`). Do not edit or delete another process's files, and do not cite `.clever/ralph/` as authority.
2. Work on a `feat/<topic>` or `fix/<topic>` branch from `main`; do not commit to `main`. Do not commit, tag or push unless asked.
3. Read one existing module end to end before writing a new one. `kms`, `security-group`, `s3-bucket` and `waf-web-acl` are the cleanest references.

## Writing a module

- Keep it to one concern. If the module needs a VPC, subnet, key, zone, certificate or role it does not own, take it as an input; do not look it up and do not create it. Only nest another module the way `alb` → `security-group` and `ecr` → `kms` do, and only when the README can say why.
- Use the standard file set and naming: `full_name = join("-", compact([var.name, var.environment, var.name_suffix]))`, `tags = merge(var.tags, { Name = local.full_name })`, main resource called `this`.
- Default to closed and encrypted: no ingress or egress, no public access, a customer-managed KMS key input (non-nullable when null would mean an AWS-managed key), TLS enforced, deletion protection where AWS offers it.
- Build IAM policies with `jsonencode` and named `Sid`s; scope every statement to the resources passed in; drop the statement when its list is empty; never emit a wildcard resource unless the action cannot be scoped (and then say so in the README).
- Add a `validation` block for every input whose bad value would otherwise fail at apply time or weaken security; use `lifecycle.precondition` for cross-input checks. Error messages are full sentences naming the variable.
- Use `data.aws_region.<x>.region`, not `.name` (provider 6).
- Do not add `configuration_aliases`. Region-bound modules document `providers = { aws = aws.us_east_1 }` in a `## Provider` README section.
- No comments in `.tf` files. Put the explanation in the variable or output description or in the README.
- Irish/British spelling in prose and descriptions.
- Placeholders only: `123456789012`, `example.com`/`example.org`/`example.test`, `example-org`, `eu-west-1`. Never copy names, hosts, account numbers or emails from a caller repository (for example `finn-app-brazil`) into this one.

## Tests and docs that must come with it

- `tests/<module>.tftest.hcl` with `mock_provider "aws"` (add `mock_data`/`mock_resource` defaults for any computed attribute you assert on), one positive run per behaviour and security default, one `expect_failures` run per validation and precondition. Use `command = plan` unless you need mocked computed values.
- `examples/basic/main.tf` that calls `source = "../.."` with the `tags` module and whatever keys it needs.
- `README.md` with the standard sections (`Owns`, `Does not own`, `Usage`, `Defaults worth knowing`, `Left out on purpose`, `Tests`, `Example`) above the terraform-docs block. Regenerate the block with `terraform-docs --config .terraform-docs.yml modules/<name>`; never hand-edit it.
- A row in the root `README.md` module table and, in the same feature commit, an entry under `## [Unreleased]` in `CHANGELOG.md` (create the heading if it is absent), with a `Migration` section for anything breaking.

## Verifying

Run `scripts/check.sh` from the repository root. It is the CI gate and needs `terraform`, `tflint`, `trivy`, `terraform-docs`, `shellcheck` and `python3`. If a tool is missing locally, run the steps you can (fmt, validate, `terraform test` per folder, the identifier guard and its test) and say exactly which steps you did not run. Do not add a `.trivyignore` entry without a one-line reason in that file and a matching note in the module README.

## Changing an existing module

- Treat every variable and output as public API used by pinned callers. Prefer adding an optional input whose default keeps today's plan unchanged.
- Renaming or removing an input or output, changing a resource address, changing naming, or tightening the provider constraint is breaking: mark it `feat!:`/**Breaking:**, write migration steps (including `moved` blocks or `terraform state mv` for address changes) and expect a minor bump while below 1.0.
- Check the real caller before calling a change safe: `grep -rn 'd-tf-modules.git//modules/<name>' ../finn-app-brazil/infra` from the hub workspace.

## Releasing (only when asked)

Branch `release/vX.Y.Z`, one commit `chore: release vX.Y.Z` that dates the CHANGELOG entry, PR to `main`, merge, then an annotated tag `vX.Y.Z` on the merge commit. Callers pin the full commit hash with `# vX.Y.Z` in a trailing comment.

## Things not to assume

- There is no lambda module on `main` yet (`README.md:25`); anything in `modules/lambda` without a commit is work in progress.
- There is no Renovate config, release automation or registry publication.
- This repository is not listed in the hub's `system-index.yml` (checked 2026-10-31).
