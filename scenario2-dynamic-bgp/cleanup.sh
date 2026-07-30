#!/usr/bin/env bash
# ===========================================================================
# Scenario 2 - Dynamic routing - Teardown
# Deletes the entire resource group created by deploy.sh.
# The Azure Route Server can take several minutes to delete.
# ===========================================================================
set -euo pipefail

read -rp "Resource group to delete [lab-zt-sdwan-s2]: " RG; RG="${RG:-lab-zt-sdwan-s2}"
read -rp "Delete resource group '${RG}' and ALL its resources? (y/N): " CONFIRM
case "${CONFIRM}" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo "Deleting '${RG}' (running in the background)..."
az group delete --name "${RG}" --yes --no-wait
echo "Delete requested. Also remove hub-nva / onprem-nva from your ZeroTier network."
