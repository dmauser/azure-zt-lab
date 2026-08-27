#!/usr/bin/env bash
# ===========================================================================
# Scenario 1 - Static routing - Teardown
# Deletes the resource group created by deploy.sh and can optionally remove the
# recorded ZeroTier members.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../scripts/lab-common.sh
source "${REPO_ROOT}/scripts/lab-common.sh"

RG="${RG:-}"
WAIT_FOR_DELETE="${LAB_CLEANUP_WAIT:-0}"

usage() {
  cat <<'EOF'
Usage: cleanup.sh [--resource-group NAME] [--wait]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --resource-group) RG="${2:?missing resource group}"; shift 2 ;;
    --wait) WAIT_FOR_DELETE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

STATE_FILE="${SCRIPT_DIR}/.deployment.env"
if [ -z "$RG" ] && [ -f "$STATE_FILE" ]; then
  RG="$(env_value RESOURCE_GROUP "$STATE_FILE")"
fi
if [ -z "$RG" ]; then
  read -rp "Resource group to delete [lab-zt-sdwan-s1]: " RG
  RG="${RG:-lab-zt-sdwan-s1}"
fi

require_commands az tr
require_azure_login
[ "$(az group exists --name "$RG" --query '@' -o tsv | tr -d '\r')" = "true" ] ||
  die "Resource group does not exist: ${RG}"

read -rp "Delete resource group '${RG}' and ALL its resources? (y/N): " CONFIRM
case "${CONFIRM}" in
  y|Y) ;;
  *) info "Cleanup cancelled."; exit 0 ;;
esac

info "Requesting deletion of '${RG}'..."
if [ "$WAIT_FOR_DELETE" = "1" ]; then
  az group delete --name "$RG" --yes
  ok "Resource group deleted."
else
  az group delete --name "$RG" --yes --no-wait
  ok "Resource-group deletion requested in the background."
fi

ZT_STATE="${SCRIPT_DIR}/.zt-overlay.env"
if [ -f "$ZT_STATE" ]; then
  read -rp "Also remove the two recorded ZeroTier members? (y/N): " ZT_CONFIRM
  if [[ "$ZT_CONFIRM" =~ ^[Yy]$ ]]; then
    ZT_NETWORK_ID="$(env_value ZT_NETWORK_ID "$ZT_STATE")"
    HUB_NODE_ID="$(env_value HUB_NODE_ID "$ZT_STATE")"
    ONPREM_NODE_ID="$(env_value ONPREM_NODE_ID "$ZT_STATE")"
    if [ -z "${ZEROTIER_API_TOKEN:-}" ]; then
      read -rsp "ZeroTier API token: " ZEROTIER_API_TOKEN
      echo
      export ZEROTIER_API_TOKEN
    fi
    # shellcheck source=../scripts/zt-api.sh
    source "${REPO_ROOT}/scripts/zt-api.sh"
    zt_require
    zt_delete_member "$ZT_NETWORK_ID" "$HUB_NODE_ID"
    zt_delete_member "$ZT_NETWORK_ID" "$ONPREM_NODE_ID"
    ok "Recorded ZeroTier members removed."
  else
    warn "ZeroTier members were left unchanged."
  fi
fi
