#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

step() {
  printf '\n== %s\n' "$1"
}

step "terraform fmt"
terraform fmt -check -recursive

step "terraform validate"
find modules examples -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; | sort -u | while read -r dir; do
  (cd "$dir" && terraform init -backend=false -input=false > /dev/null && terraform validate -no-color)
done

step "terraform test"
for dir in modules/* examples/ordering-agent; do
  (cd "$dir" && terraform init -backend=false -input=false > /dev/null && terraform test -no-color)
done

step "tflint"
tflint --init > /dev/null
tflint --recursive --config="$root/.tflint.hcl"

step "trivy config"
trivy config --ignorefile .trivyignore --severity HIGH,CRITICAL --exit-code 1 --skip-dirs '**/.terraform' .

step "terraform-docs"
for dir in modules/*; do
  terraform-docs --config .terraform-docs.yml --output-check "$dir"
done

step "foreign identifiers"
scripts/check-no-foreign-identifiers.sh
tests/check-no-foreign-identifiers.test.sh

step "shellcheck"
shellcheck scripts/*.sh tests/*.sh
