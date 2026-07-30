#!/usr/bin/env bash
# ===========================================================================
# Scenario 1 - Static routing - Teardown
# Deletes the entire resource group created by deploy.sh.
# ===========================================================================
set -euo pipefail

read -rp "Resource group to delete [lab-zt-sdwan-s1]: " RG; RG="${RG:-lab-zt-sdwan-s1}"
read -rp "Delete resource group '${RG}' and ALL its resources? (y/N): " CONFIRM
case "${CONFIRM}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo "Deleting '${RG}' (running in the background)..."
az group delete --name "${RG}" --yes --no-wait
echo "Delete requested. Also remember to remove hub-nva / onprem-nva from your ZeroTier network."
