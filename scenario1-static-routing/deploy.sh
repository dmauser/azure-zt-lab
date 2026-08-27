#!/usr/bin/env bash
# ===========================================================================
# Scenario 1 - Static routing - Deployment wrapper
# ---------------------------------------------------------------------------
# 1. Prompts for an SSH public key + ZeroTier network ID.
# 2. Deploys the Bicep infrastructure (VNets, NVAs, VMs, UDRs).
# 3. Installs ZeroTier on both NVAs and joins them to your network.
#
# Run from Azure Cloud Shell (bash) or any machine with the Azure CLI logged in.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../scripts/lab-common.sh
source "${REPO_ROOT}/scripts/lab-common.sh"

usage() {
  cat <<'EOF'
Usage: deploy.sh [options]

Options:
  --resource-group NAME
  --location REGION
  --vm-size SKU
  --admin-user NAME
  --ssh-key-file PATH
  --ssh-source IPV4[/PREFIX]
  --zerotier-network-id ID
  --skip-what-if

The corresponding environment variables are RG, LOCATION, VMSIZE, ADMIN_USER,
SSH_KEY_FILE, SSH_SRC, ZT_NETID, and LAB_SKIP_WHAT_IF=1.
EOF
}

RG="${RG:-}"
LOCATION="${LOCATION:-}"
VMSIZE="${VMSIZE:-}"
ADMIN_USER="${ADMIN_USER:-}"
SSH_KEY_FILE="${SSH_KEY_FILE:-}"
SSH_SRC="${SSH_SRC:-}"
ZT_NETID="${ZT_NETID:-}"
LAB_SKIP_WHAT_IF="${LAB_SKIP_WHAT_IF:-0}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --resource-group) RG="${2:?missing resource group}"; shift 2 ;;
    --location) LOCATION="${2:?missing location}"; shift 2 ;;
    --vm-size) VMSIZE="${2:?missing VM size}"; shift 2 ;;
    --admin-user) ADMIN_USER="${2:?missing admin user}"; shift 2 ;;
    --ssh-key-file) SSH_KEY_FILE="${2:?missing SSH key file}"; shift 2 ;;
    --ssh-source) SSH_SRC="${2:?missing SSH source}"; shift 2 ;;
    --zerotier-network-id) ZT_NETID="${2:?missing ZeroTier network ID}"; shift 2 ;;
    --skip-what-if) LAB_SKIP_WHAT_IF=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

bold "== Scenario 1: ZeroTier + Azure Hub & Spoke (static routing) =="
require_commands az curl base64 sed grep
require_azure_login

if [ -z "$RG" ]; then read -rp "Resource group name [lab-zt-sdwan-s1]: " RG; fi
RG="${RG:-lab-zt-sdwan-s1}"
if [ -z "$LOCATION" ]; then read -rp "Location [centralus]: " LOCATION; fi
LOCATION="${LOCATION:-centralus}"
if [ -z "$VMSIZE" ]; then read -rp "VM size [Standard_DS1_v2]: " VMSIZE; fi
VMSIZE="${VMSIZE:-Standard_DS1_v2}"
if [ -z "$ADMIN_USER" ]; then read -rp "Admin username [azureuser]: " ADMIN_USER; fi
ADMIN_USER="${ADMIN_USER:-azureuser}"
if [ -z "$SSH_KEY_FILE" ]; then
  read -rp "SSH public key file [${HOME}/.ssh/id_ed25519.pub]: " SSH_KEY_FILE
fi
SSH_KEY_FILE="${SSH_KEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"
SSH_KEY_FILE="${SSH_KEY_FILE/#\~/${HOME}}"
SSH_PUBLIC_KEY="$(read_ssh_public_key "$SSH_KEY_FILE")"
if [ -z "$ZT_NETID" ]; then read -rp "ZeroTier network ID: " ZT_NETID; fi
valid_zt_network_id "$ZT_NETID" || die "ZeroTier network ID must be 16 hexadecimal characters."

# Your public IP is used to lock down SSH access.
if [ -z "$SSH_SRC" ]; then
  MY_IP="$(resolve_public_ip || true)"
  read -rp "Allow SSH from source IP [${MY_IP}]: " SSH_SRC
  SSH_SRC="${SSH_SRC:-$MY_IP}"
fi
valid_ipv4_source "$SSH_SRC" || die "SSH source must be a valid IPv4 address or CIDR."
[[ "$SSH_SRC" == */* ]] || SSH_SRC="${SSH_SRC}/32"

NVA_CLOUDINIT_B64="$(b64_file "${REPO_ROOT}/scripts/cloud-init-nva.yaml")"
TOOLS_CLOUDINIT_B64="$(b64_file "${REPO_ROOT}/scripts/cloud-init-tools.yaml")"
DEPLOYMENT_NAME="scenario1-$(date +%Y%m%d-%H%M%S)"
DEPLOY_ARGS=(
  --resource-group "$RG"
  --name "$DEPLOYMENT_NAME"
  --template-file "${SCRIPT_DIR}/main.bicep"
  --parameters
    "location=${LOCATION}"
    "vmSize=${VMSIZE}"
    "adminUsername=${ADMIN_USER}"
    "sshPublicKey=${SSH_PUBLIC_KEY}"
    "allowedSshSourceIp=${SSH_SRC}"
    "nvaCloudInit=${NVA_CLOUDINIT_B64}"
    "toolsCloudInit=${TOOLS_CLOUDINIT_B64}"
)

# ----- deploy --------------------------------------------------------------
info "Creating resource group '${RG}' in '${LOCATION}'..."
az group create --name "${RG}" --location "${LOCATION}" -o none

info "Building and validating Bicep..."
az bicep build --file "${SCRIPT_DIR}/main.bicep" --stdout >/dev/null
az deployment group validate "${DEPLOY_ARGS[@]}" --only-show-errors -o none
if [ "$LAB_SKIP_WHAT_IF" != "1" ]; then
  info "Previewing Azure changes..."
  az deployment group what-if "${DEPLOY_ARGS[@]}" --no-pretty-print -o jsonc
fi

info "Deploying infrastructure (this takes a few minutes)..."
az deployment group create "${DEPLOY_ARGS[@]}" --only-show-errors -o none
write_deployment_state "${SCRIPT_DIR}/.deployment.env" "$RG" "$DEPLOYMENT_NAME" "$LOCATION"
ok "Infrastructure deployed."

# ----- ZeroTier install + join --------------------------------------------
info "Installing ZeroTier on the NVAs and joining network ${ZT_NETID}..."
for nva in hub-nva onprem-nva; do
  az_vm_install_zerotier "$RG" "$nva"
  az_vm_run "$RG" "$nva" "sudo zerotier-cli join ${ZT_NETID}"
  ok "ZeroTier joined on ${nva}."
done

# ----- ZeroTier authorize + pin overlay IPs (optional, needs API token) ----
# Supply a token via the ZEROTIER_API_TOKEN env var or the prompt below to
# authorize both members automatically. Press Enter at the prompt to skip and
# authorize manually in the portal instead.
source "${REPO_ROOT}/scripts/zt-postdeploy.sh"
ZT_STATUS=0
zt_postdeploy "${RG}" "${ZT_NETID}" "${SCRIPT_DIR}/.zt-overlay.env" || ZT_STATUS=$?
case "$ZT_STATUS" in
  0) "${SCRIPT_DIR}/apply-routes.sh" --resource-group "${RG}" ;;
  2)
    POSTDEPLOY_PENDING=1
    warn "Complete manual authorization, then run ./apply-routes.sh."
    ;;
  *) die "ZeroTier authorization failed; Azure resources remain in ${RG} for troubleshooting." ;;
esac

# ----- summary -------------------------------------------------------------
echo
bold "== Deployment complete =="
az deployment group show -g "${RG}" -n "${DEPLOYMENT_NAME}" --query properties.outputs -o jsonc

cat <<EOF

Next steps:
  1. Validate connectivity — from onprem-vm1 ping a spoke VM across the overlay
     (e.g. ping 10.0.1.4). See README.md for the full verification steps.

Tear down with:  ./cleanup.sh
EOF

if [ "${POSTDEPLOY_PENDING:-0}" = "1" ]; then
  exit 2
fi
