#!/usr/bin/env bash
# ===========================================================================
# Scenario 2 - Dynamic routing (BGP + Azure Route Server) - Deployment wrapper
# ---------------------------------------------------------------------------
# 1. Prompts for credentials + ZeroTier network ID.
# 2. Deploys the Bicep infra (VNets, NVAs, VMs, Azure Route Server, peerings).
#    NOTE: the Route Server adds ~15-20 min to the deployment.
# 3. Installs ZeroTier on both NVAs and joins them to your network.
#
# After this finishes: authorize the NVAs in the ZeroTier portal, then run
# ./apply-frr.sh to bring up BGP.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m[info]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[ ok ]\033[0m %s\n' "$*"; }

b64() {
  if base64 --help 2>&1 | grep -q -- '-w'; then base64 -w0 "$1"; else base64 "$1" | tr -d '\n'; fi
}

bold "== Scenario 2: ZeroTier + Azure Route Server (dynamic BGP routing) =="

read -rp "Resource group name [lab-zt-sdwan-s2]: " RG;            RG="${RG:-lab-zt-sdwan-s2}"
read -rp "Location [centralus]: " LOCATION;                       LOCATION="${LOCATION:-centralus}"
read -rp "VM size [Standard_DS1_v2]: " VMSIZE;                    VMSIZE="${VMSIZE:-Standard_DS1_v2}"
read -rp "Admin username [azureuser]: " ADMIN_USER;              ADMIN_USER="${ADMIN_USER:-azureuser}"
read -rsp "Admin password: " ADMIN_PASS; echo
read -rp  "ZeroTier network ID: " ZT_NETID
[ -n "${ZT_NETID}" ] || { echo "ZeroTier network ID is required." >&2; exit 1; }

MY_IP="$(curl -s -4 ifconfig.me || true)"
read -rp "Allow SSH from source IP [${MY_IP}]: " SSH_SRC;         SSH_SRC="${SSH_SRC:-$MY_IP}"
[ -n "${SSH_SRC}" ] || { echo "Could not determine your public IP; please supply one." >&2; exit 1; }

NVA_CLOUDINIT_B64="$(b64 "${REPO_ROOT}/scripts/cloud-init-nva.yaml")"
TOOLS_CLOUDINIT_B64="$(b64 "${REPO_ROOT}/scripts/cloud-init-tools.yaml")"

info "Creating resource group '${RG}' in '${LOCATION}'..."
az group create --name "${RG}" --location "${LOCATION}" -o none

info "Deploying infrastructure incl. Azure Route Server (this can take ~20 min)..."
az deployment group create \
  --resource-group "${RG}" \
  --name "scenario2-$(date +%Y%m%d-%H%M%S)" \
  --template-file "${SCRIPT_DIR}/main.bicep" \
  --parameters \
      location="${LOCATION}" \
      vmSize="${VMSIZE}" \
      adminUsername="${ADMIN_USER}" \
      adminPassword="${ADMIN_PASS}" \
      allowedSshSourceIp="${SSH_SRC}" \
      nvaCloudInit="${NVA_CLOUDINIT_B64}" \
      toolsCloudInit="${TOOLS_CLOUDINIT_B64}" \
  -o none
ok "Infrastructure deployed."

info "Installing ZeroTier on the NVAs and joining network ${ZT_NETID}..."
for nva in hub-nva onprem-nva; do
  az vm run-command invoke -g "${RG}" -n "${nva}" --command-id RunShellScript \
    --scripts "curl -s https://install.zerotier.com | sudo bash && sudo zerotier-cli join ${ZT_NETID}" \
    --only-show-errors -o none
  ok "ZeroTier joined on ${nva}."
done

echo
bold "== Deployment complete =="
az deployment group show -g "${RG}" -n "$(az deployment group list -g "${RG}" --query "[?contains(name,'scenario2')].name | [0]" -o tsv)" \
  --query properties.outputs -o jsonc || true

cat <<EOF

Next steps:
  1. Authorize hub-nva + onprem-nva in https://my.zerotier.com/ and note their
     overlay IPs (see ../docs/zerotier-setup.md).
  2. Bring up BGP:   ./apply-frr.sh
  3. Verify learned routes (see README).

Tear down with:  ./cleanup.sh
EOF
