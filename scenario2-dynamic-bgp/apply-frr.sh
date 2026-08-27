#!/usr/bin/env bash
# ===========================================================================
# Scenario 2 - Render + apply FRR BGP config to both NVAs
# ---------------------------------------------------------------------------
# Run this after deploy.sh and ZeroTier authorization.
#
# It fills in the FRR templates in ./frr with the real ASNs / IPs, enables
# bgpd, installs the config, and restarts FRR on each NVA via run-command.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../scripts/lab-common.sh
source "${REPO_ROOT}/scripts/lab-common.sh"

HUB_NVA_ASN=65001
ONPREM_NVA_ASN=65002
HUB_NVA_IP=10.0.0.36
ONPREM_NVA_IP=192.168.100.36
RG="${RG:-}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-}"
HUB_OVERLAY="${HUB_OVERLAY_IP:-}"
ONPREM_OVERLAY="${ONPREM_OVERLAY_IP:-}"

usage() {
  cat <<'EOF'
Usage: apply-frr.sh [options]

Options:
  --resource-group NAME
  --deployment-name NAME
  --hub-overlay-ip IPV4
  --onprem-overlay-ip IPV4
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --resource-group) RG="${2:?missing resource group}"; shift 2 ;;
    --deployment-name) DEPLOYMENT_NAME="${2:?missing deployment name}"; shift 2 ;;
    --hub-overlay-ip) HUB_OVERLAY="${2:?missing hub overlay IP}"; shift 2 ;;
    --onprem-overlay-ip) ONPREM_OVERLAY="${2:?missing on-prem overlay IP}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

bold "== Scenario 2: apply FRR/BGP config =="
require_commands az base64 grep sed
require_azure_login

ENV_FILE="${SCRIPT_DIR}/.zt-overlay.env"
if [ -f "${ENV_FILE}" ]; then
  [ -n "$HUB_OVERLAY" ] || HUB_OVERLAY="$(env_value HUB_OVERLAY_IP "${ENV_FILE}")"
  [ -n "$ONPREM_OVERLAY" ] || ONPREM_OVERLAY="$(env_value ONPREM_OVERLAY_IP "${ENV_FILE}")"
  [ -n "${HUB_OVERLAY}" ] && [ -n "${ONPREM_OVERLAY}" ] && \
    info "Overlay IPs from .zt-overlay.env: hub=${HUB_OVERLAY} onprem=${ONPREM_OVERLAY}"
fi

DEPLOYMENT_STATE="${SCRIPT_DIR}/.deployment.env"
if [ -f "$DEPLOYMENT_STATE" ]; then
  [ -n "$RG" ] || RG="$(env_value RESOURCE_GROUP "$DEPLOYMENT_STATE")"
  [ -n "$DEPLOYMENT_NAME" ] || DEPLOYMENT_NAME="$(env_value DEPLOYMENT_NAME "$DEPLOYMENT_STATE")"
fi
if [ -z "$RG" ]; then
  read -rp "Resource group [lab-zt-sdwan-s2]: " RG
  RG="${RG:-lab-zt-sdwan-s2}"
fi
if [ -z "$DEPLOYMENT_NAME" ]; then
  read -rp "Exact deployment name: " DEPLOYMENT_NAME
fi
[ -n "$DEPLOYMENT_NAME" ] || die "Deployment name is required. Re-run deploy.sh or pass --deployment-name."

if [ -z "${HUB_OVERLAY:-}" ] || [ -z "${ONPREM_OVERLAY:-}" ]; then
  read -rp "hub-nva ZeroTier overlay IP [172.27.0.10]: "    HUB_OVERLAY;    HUB_OVERLAY="${HUB_OVERLAY:-172.27.0.10}"
  read -rp "onprem-nva ZeroTier overlay IP [172.27.0.20]: " ONPREM_OVERLAY; ONPREM_OVERLAY="${ONPREM_OVERLAY:-172.27.0.20}"
fi
valid_ipv4 "$HUB_OVERLAY" || die "Invalid hub overlay IP: ${HUB_OVERLAY}"
valid_ipv4 "$ONPREM_OVERLAY" || die "Invalid on-prem overlay IP: ${ONPREM_OVERLAY}"
[ "$HUB_OVERLAY" != "$ONPREM_OVERLAY" ] || die "Overlay IPs must be different."

info "Reading Route Server BGP IPs from the deployment outputs..."
mapfile -t RS_IPS < <(az deployment group show -g "${RG}" -n "${DEPLOYMENT_NAME}" \
  --query "properties.outputs.routeServerIps.value[]" -o tsv | tr -d '\r')
[ "${#RS_IPS[@]}" -eq 2 ] || die "Could not read two Route Server IPs from deployment ${DEPLOYMENT_NAME}."
if ! valid_ipv4 "${RS_IPS[0]}" || ! valid_ipv4 "${RS_IPS[1]}"; then
  die "Deployment outputs contain invalid Route Server IPs."
fi
ok "Route Server IPs: ${RS_IPS[0]}, ${RS_IPS[1]}"

render() { # <template> <output>
  sed -e "s|__HUB_NVA_ASN__|${HUB_NVA_ASN}|g" \
      -e "s|__ONPREM_NVA_ASN__|${ONPREM_NVA_ASN}|g" \
      -e "s|__HUB_NVA_IP__|${HUB_NVA_IP}|g" \
      -e "s|__ONPREM_NVA_IP__|${ONPREM_NVA_IP}|g" \
      -e "s|__ROUTE_SERVER_IP_1__|${RS_IPS[0]}|g" \
      -e "s|__ROUTE_SERVER_IP_2__|${RS_IPS[1]}|g" \
      -e "s|__HUB_NVA_OVERLAY_IP__|${HUB_OVERLAY}|g" \
      -e "s|__ONPREM_NVA_OVERLAY_IP__|${ONPREM_OVERLAY}|g" \
      "$1" > "$2"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
render "${SCRIPT_DIR}/frr/hub-nva.frr.conf.tmpl"    "${TMP}/hub-nva.frr.conf"
render "${SCRIPT_DIR}/frr/onprem-nva.frr.conf.tmpl" "${TMP}/onprem-nva.frr.conf"

push_frr() { # <vm-name> <rendered-conf>
  local vm="$1" conf="$2" b64
  b64="$(b64_file "$conf")"
  info "Applying FRR config to ${vm}..."
  az_vm_run "$RG" "$vm" \
    "printf '%s' '${b64}' | base64 -d | sudo tee /tmp/zt-lab-frr.conf >/dev/null
sudo /usr/lib/frr/frr-reload.py --test /tmp/zt-lab-frr.conf
sudo install -o frr -g frr -m 0640 /tmp/zt-lab-frr.conf /etc/frr/frr.conf
sudo rm -f /tmp/zt-lab-frr.conf
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl enable frr
sudo systemctl restart frr
sudo systemctl is-active --quiet frr"
  ok "${vm} configured."
}

push_frr hub-nva    "${TMP}/hub-nva.frr.conf"
push_frr onprem-nva "${TMP}/onprem-nva.frr.conf"

wait_bgp() { # <vm-name> <expected-established-peers> <required-prefix>
  local vm="$1" expected="$2" prefix="$3" result
  info "Waiting for ${vm} BGP convergence..."
  result="$(az_vm_run "$RG" "$vm" \
    "converged=0
for attempt in \$(seq 1 36); do
  summary=\$(sudo vtysh -c 'show bgp ipv4 unicast summary json' | tr -d '[:space:]')
  count=\$(printf '%s' \"\$summary\" | grep -o '\"state\":\"Established\"' | wc -l)
  route=\$(sudo vtysh -c 'show ip bgp ${prefix} json' | tr -d '[:space:]')
  if [ \"\$count\" -ge ${expected} ] && printf '%s' \"\$route\" | grep -q '\"prefix\":\"${prefix}\"'; then
    sudo vtysh -c 'show ip bgp summary'
    converged=1
    break
  fi
  sleep 5
done
if [ \"\$converged\" -ne 1 ]; then
  sudo vtysh -c 'show ip bgp summary'
  false
fi")"
  printf '%s\n' "$result"
  ok "${vm} has ${expected} established peer(s) and route ${prefix}."
}

wait_bgp hub-nva 3 192.168.100.0/24
wait_bgp onprem-nva 1 10.0.1.0/24

cat <<EOF

FRR applied. Verify with:
  # On hub-nva / onprem-nva:
  sudo vtysh -c "show ip bgp summary"     # sessions should be Established
  sudo vtysh -c "show ip bgp"             # learned prefixes

  # From Azure (routes the Route Server learned from the hub NVA):
  az network routeserver peering list-learned-routes \\
    --routeserver hub-route-server -g ${RG} --name hub-nva
EOF
