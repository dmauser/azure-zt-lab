#!/usr/bin/env bash
# ===========================================================================
# scripts/zt-api.sh — ZeroTier Central REST API helpers
# ---------------------------------------------------------------------------
# Automates the one manual lab step: authorizing the NVA members and pinning
# their overlay IPs, instead of clicking "Auth?" in the ZeroTier portal.
#
# Usage:
#   * Source it from another script:   source scripts/zt-api.sh
#   * Or run it directly to authorize + pin a single member:
#       ZEROTIER_API_TOKEN=... ./scripts/zt-api.sh <networkId> <nodeId> <name> [overlayIp]
#
# Requires: curl, jq, and a ZeroTier Central API token.
#   Create a token at https://my.zerotier.com/  ->  Account -> API Access Tokens
#   then export it:   export ZEROTIER_API_TOKEN="<token>"
#
# All functions are idempotent and never print the token.
# ===========================================================================

# Canonical Central API base (legacy my.zerotier.com/api/v1 still redirects here).
ZT_API_BASE="${ZT_API_BASE:-https://api.zerotier.com/api/v1}"

# zt_require — verify curl + jq are present. Returns non-zero with a clear message.
zt_require() {
  command -v curl >/dev/null 2>&1 || { echo "zt-api: 'curl' is required but not found" >&2; return 1; }
  command -v jq   >/dev/null 2>&1 || { echo "zt-api: 'jq' is required but not found"   >&2; return 1; }
}

# _zt_curl METHOD PATH [json-body]
# Internal. Prints the response body to stdout; returns non-zero on HTTP >= 400.
_zt_curl() {
  local method="$1" path="$2" body="${3:-}"
  local token="${ZEROTIER_API_TOKEN:-}"
  [ -n "$token" ] || { echo "zt-api: ZEROTIER_API_TOKEN is not set" >&2; return 1; }

  local url="${ZT_API_BASE}${path}" tmp code
  tmp="$(mktemp)"
  if [ -n "$body" ]; then
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: token ${token}" \
      -H "Content-Type: application/json" \
      -d "$body" || true)"
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: token ${token}" || true)"
  fi
  cat "$tmp"; rm -f "$tmp"

  if [ -z "${code}" ] || [ "${code}" -ge 400 ] 2>/dev/null; then
    echo "zt-api: ${method} ${path} -> HTTP ${code:-000}" >&2
    return 1
  fi
}

# zt_get_member NETWORK_ID NODE_ID  ->  member JSON on stdout
zt_get_member() {
  _zt_curl GET "/network/$1/member/$2"
}

# zt_authorize_member NETWORK_ID NODE_ID NAME [OVERLAY_IP]
# Authorizes the member and (optionally) pins a fixed overlay IP. Idempotent.
zt_authorize_member() {
  local net="$1" node="$2" name="$3" ip="${4:-}" cfg payload
  if [ -n "$ip" ]; then
    cfg="$(jq -nc --arg ip "$ip" '{authorized:true, ipAssignments:[$ip]}')"
  else
    cfg="$(jq -nc '{authorized:true}')"
  fi
  payload="$(jq -nc --arg name "$name" --argjson config "$cfg" '{name:$name, config:$config}')"
  _zt_curl POST "/network/$net/member/$node" "$payload" >/dev/null
}

# zt_member_overlay_ip NETWORK_ID NODE_ID  ->  first assigned overlay IP (or empty)
zt_member_overlay_ip() {
  zt_get_member "$1" "$2" | jq -r '.config.ipAssignments[0] // empty'
}

# zt_member_authorized NETWORK_ID NODE_ID  ->  "true" / "false"
zt_member_authorized() {
  zt_get_member "$1" "$2" | jq -r '.config.authorized // false'
}

# zt_wait_member_online NETWORK_ID NODE_ID [TIMEOUT_SECS=90]
# Polls until the member is authorized AND has an overlay IP; prints the IP.
zt_wait_member_online() {
  local net="$1" node="$2" timeout="${3:-90}" waited=0 j auth ip
  while [ "$waited" -lt "$timeout" ]; do
    j="$(zt_get_member "$net" "$node" 2>/dev/null || true)"
    auth="$(printf '%s' "$j" | jq -r '.config.authorized // false' 2>/dev/null || echo false)"
    ip="$(printf '%s' "$j" | jq -r '.config.ipAssignments[0] // empty' 2>/dev/null || true)"
    if [ "$auth" = "true" ] && [ -n "$ip" ]; then
      printf '%s\n' "$ip"; return 0
    fi
    sleep 3; waited=$((waited + 3))
  done
  echo "zt-api: member ${node} not authorized/online within ${timeout}s" >&2
  return 1
}

# ---- direct invocation: authorize + pin one member -------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -euo pipefail
  zt_require
  if [ "$#" -lt 3 ]; then
    echo "usage: ZEROTIER_API_TOKEN=... $0 <networkId> <nodeId> <name> [overlayIp]" >&2
    exit 1
  fi
  zt_authorize_member "$1" "$2" "$3" "${4:-}"
  ip="$(zt_wait_member_online "$1" "$2" 90)"
  echo "authorized ${3} (${2}) -> ${ip}"
fi
