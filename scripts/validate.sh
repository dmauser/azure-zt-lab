#!/usr/bin/env bash
# Run all non-deployment repository quality checks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=lab-common.sh
source "${SCRIPT_DIR}/lab-common.sh"

require_commands az bash git

mapfile -d '' SHELL_FILES < <(find . -type f -name '*.sh' -not -path './.git/*' -print0)
mapfile -d '' BICEP_FILES < <(find modules scenario1-static-routing scenario2-dynamic-bgp \
  -type f -name '*.bicep' -print0)
mapfile -d '' MERMAID_FILES < <(find docs -type f -name '*.mmd' -print0)

info "Checking shell syntax..."
bash -n "${SHELL_FILES[@]}"

if command -v shellcheck >/dev/null 2>&1; then
  info "Running ShellCheck..."
  shellcheck -x -P SCRIPTDIR "${SHELL_FILES[@]}"
elif [ "${CI:-false}" = "true" ]; then
  die "shellcheck is required in CI."
else
  warn "shellcheck is not installed; skipping static shell analysis."
fi

info "Building and linting Bicep..."
for bicep_file in "${BICEP_FILES[@]}"; do
  az bicep lint --file "$bicep_file" --only-show-errors
done
az bicep build --file scenario1-static-routing/main.bicep --stdout >/dev/null
az bicep build --file scenario2-dynamic-bgp/main.bicep --stdout >/dev/null

if command -v cloud-init >/dev/null 2>&1; then
  info "Validating cloud-init schemas..."
  cloud-init schema --config-file scripts/cloud-init-nva.yaml
  cloud-init schema --config-file scripts/cloud-init-tools.yaml
elif [ "${CI:-false}" = "true" ]; then
  die "cloud-init is required in CI."
else
  warn "cloud-init is not installed; skipping schema validation."
fi

info "Checking Markdown links..."
bash scripts/check-markdown-links.sh

if command -v mmdc >/dev/null 2>&1; then
  info "Rendering Mermaid sources..."
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  for mermaid_file in "${MERMAID_FILES[@]}"; do
    mmdc --input "$mermaid_file" --output "${tmp_dir}/$(basename "${mermaid_file%.mmd}").svg" \
      --backgroundColor white --quiet
  done
elif [ "${CI:-false}" = "true" ]; then
  die "mmdc is required in CI."
else
  warn "mmdc is not installed; skipping Mermaid rendering."
fi

git diff --check
ok "Repository validation passed."
