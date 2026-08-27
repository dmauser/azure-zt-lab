#!/usr/bin/env bash
# Configure persistent static routes between the Azure and simulated on-premises
# sites after the ZeroTier members have received their overlay addresses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../scripts/lab-common.sh
source "${REPO_ROOT}/scripts/lab-common.sh"
RG="${RG:-}"
HUB_OVERLAY="${HUB_OVERLAY_IP:-}"
ONPREM_OVERLAY="${ONPREM_OVERLAY_IP:-}"

usage() {
  cat <<'EOF'
Usage: apply-routes.sh [options]

Options:
  --resource-group NAME
  --hub-overlay-ip IPV4
  --onprem-overlay-ip IPV4
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --resource-group) RG="${2:?missing resource group}"; shift 2 ;;
    --hub-overlay-ip) HUB_OVERLAY="${2:?missing hub overlay IP}"; shift 2 ;;
    --onprem-overlay-ip) ONPREM_OVERLAY="${2:?missing on-prem overlay IP}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

ENV_FILE="${SCRIPT_DIR}/.zt-overlay.env"
if [ -f "$ENV_FILE" ]; then
  [ -n "$HUB_OVERLAY" ] || HUB_OVERLAY="$(env_value HUB_OVERLAY_IP "$ENV_FILE")"
  [ -n "$ONPREM_OVERLAY" ] || ONPREM_OVERLAY="$(env_value ONPREM_OVERLAY_IP "$ENV_FILE")"
fi

if [ -z "$RG" ]; then
  read -rp "Resource group [lab-zt-sdwan-s1]: " RG
  RG="${RG:-lab-zt-sdwan-s1}"
fi
if [ -z "$HUB_OVERLAY" ]; then
  read -rp "hub-nva ZeroTier overlay IP [172.27.0.10]: " HUB_OVERLAY
  HUB_OVERLAY="${HUB_OVERLAY:-172.27.0.10}"
fi
if [ -z "$ONPREM_OVERLAY" ]; then
  read -rp "onprem-nva ZeroTier overlay IP [172.27.0.20]: " ONPREM_OVERLAY
  ONPREM_OVERLAY="${ONPREM_OVERLAY:-172.27.0.20}"
fi

valid_ipv4 "$HUB_OVERLAY" || die "invalid hub overlay IP: $HUB_OVERLAY"
valid_ipv4 "$ONPREM_OVERLAY" || die "invalid on-prem overlay IP: $ONPREM_OVERLAY"
require_commands az base64 grep sed
require_azure_login

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_route_script() {
  local path="$1" next_hop="$2"; shift 2
  {
    cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
next_hop=${next_hop}
for attempt in {1..60}; do
  if ip route get "\$next_hop" 2>/dev/null | grep -q ' dev zt'; then
    break
  fi
  if [ "\$attempt" -eq 60 ]; then
    echo "ZeroTier next hop \$next_hop is not reachable" >&2
    exit 1
  fi
  sleep 2
done
EOF
    local prefix next_hop_ref
    printf -v next_hop_ref '$%s' next_hop
    for prefix in "$@"; do
      printf 'ip route replace %q via "%s"\n' "$prefix" "$next_hop_ref"
    done
  } > "$path"
}

write_route_script "$TMP/hub-routes.sh" "$ONPREM_OVERLAY" "192.168.100.0/24"
write_route_script "$TMP/onprem-routes.sh" "$HUB_OVERLAY" "10.0.0.0/16"

cat > "$TMP/zt-lab-static-routes.service" <<'EOF'
[Unit]
Description=Azure ZeroTier lab static site routes
Wants=network-online.target zerotier-one.service
After=network-online.target zerotier-one.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/zt-lab-static-routes
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

push_routes() {
  local vm="$1" route_file="$2" route_b64 unit_b64
  route_b64="$(b64_file "$route_file")"
  unit_b64="$(b64_file "$TMP/zt-lab-static-routes.service")"

  info "Installing persistent static routes on ${vm}..."
  az_vm_run "$RG" "$vm" \
    "printf '%s' '$route_b64' | base64 -d | sudo tee /usr/local/sbin/zt-lab-static-routes >/dev/null
printf '%s' '$unit_b64' | base64 -d | sudo tee /etc/systemd/system/zt-lab-static-routes.service >/dev/null
sudo chmod 0755 /usr/local/sbin/zt-lab-static-routes
sudo systemctl daemon-reload
sudo systemctl enable --now zt-lab-static-routes.service
sudo systemctl is-active --quiet zt-lab-static-routes.service"
  ok "${vm} static routes installed."
}

push_routes hub-nva "$TMP/hub-routes.sh"
push_routes onprem-nva "$TMP/onprem-routes.sh"

info "Verifying installed routes..."
az_vm_run "$RG" hub-nva \
  "ip route show 192.168.100.0/24 | grep -F 'via ${ONPREM_OVERLAY}'"
az_vm_run "$RG" onprem-nva \
  "ip route show 10.0.0.0/16 | grep -F 'via ${HUB_OVERLAY}'"
ok "Scenario 1 static site routes are active and persistent."
