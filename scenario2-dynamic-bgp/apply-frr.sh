#!/usr/bin/env bash
# ===========================================================================
# Scenario 2 - Render + apply FRR BGP config to both NVAs
# ---------------------------------------------------------------------------
# Run this AFTER deploy.sh has finished and AFTER you have authorized both
# NVAs in the ZeroTier portal (so they have stable overlay IPs).
#
# It fills in the FRR templates in ./frr with the real ASNs / IPs, enables
# bgpd, installs the config, and restarts FRR on each NVA via run-command.
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m[info]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[ ok ]\033[0m %s\n' "$*"; }

HUB_NVA_ASN=65001
ONPREM_NVA_ASN=65002
HUB_NVA_IP=10.0.0.36
ONPREM_NVA_IP=192.168.100.36

bold "== Scenario 2: apply FRR/BGP config =="
read -rp "Resource group [lab-zt-sdwan-s2]: " RG; RG="${RG:-lab-zt-sdwan-s2}"
read -rp "hub-nva ZeroTier overlay IP: "    HUB_OVERLAY
read -rp "onprem-nva ZeroTier overlay IP: " ONPREM_OVERLAY
[ -n "${HUB_OVERLAY}" ] && [ -n "${ONPREM_OVERLAY}" ] || { echo "Both overlay IPs are required." >&2; exit 1; }

info "Reading Route Server BGP IPs from the deployment outputs..."
DEP="$(az deployment group list -g "${RG}" --query "[?contains(name,'scenario2')].name | [0]" -o tsv)"
mapfile -t RS_IPS < <(az deployment group show -g "${RG}" -n "${DEP}" \
  --query "properties.outputs.routeServerIps.value" -o tsv)
[ "${#RS_IPS[@]}" -ge 2 ] || { echo "Could not read two Route Server IPs from outputs." >&2; exit 1; }
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
render "${SCRIPT_DIR}/frr/hub-nva.frr.conf.tmpl"    "${TMP}/hub-nva.frr.conf"
render "${SCRIPT_DIR}/frr/onprem-nva.frr.conf.tmpl" "${TMP}/onprem-nva.frr.conf"

push_frr() { # <vm-name> <rendered-conf>
  local vm="$1" conf b64
  b64="$(base64 -w0 "$2" 2>/dev/null || base64 "$2" | tr -d '\n')"
  info "Applying FRR config to ${vm}..."
  az vm run-command invoke -g "${RG}" -n "${vm}" --command-id RunShellScript --only-show-errors -o none \
    --scripts \
      "sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons" \
      "echo ${b64} | base64 -d | sudo tee /etc/frr/frr.conf >/dev/null" \
      "sudo systemctl enable frr" \
      "sudo systemctl restart frr" \
      "sudo vtysh -c 'show ip bgp summary' || true"
  ok "${vm} configured."
}

push_frr hub-nva    "${TMP}/hub-nva.frr.conf"
push_frr onprem-nva "${TMP}/onprem-nva.frr.conf"
rm -rf "${TMP}"

cat <<EOF

FRR applied. Verify with:
  # On hub-nva / onprem-nva:
  sudo vtysh -c "show ip bgp summary"     # sessions should be Established
  sudo vtysh -c "show ip bgp"             # learned prefixes

  # From Azure (routes the Route Server learned from the hub NVA):
  az network routeserver peering list-learned-routes \\
    --routeserver hub-route-server -g ${RG} --name hub-nva
EOF
