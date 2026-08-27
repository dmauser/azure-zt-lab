#!/usr/bin/env bash
# ===========================================================================
# scripts/zt-api.sh — ZeroTier Central REST API helpers
# ---------------------------------------------------------------------------
# Automates member authorization and deterministic overlay addressing with the
# Legacy Central API v1. This path remains available to free/legacy accounts.
#
# Usage:
#   * Source it from another script:   source scripts/zt-api.sh
#   * Or run it directly to authorize + pin a single member:
#       ZEROTIER_API_TOKEN=... ./scripts/zt-api.sh <networkId> <nodeId> <name> [overlayIp]
#
# Requires: curl, jq, and a Legacy Central API token.
#   See https://docs.zerotier.com/tokens/
#   then export it:   export ZEROTIER_API_TOKEN="<token>"
#
# All functions are idempotent and never print the token.
# ===========================================================================

# Canonical Legacy Central API base.
ZT_API_BASE="${ZT_API_BASE:-https://api.zerotier.com/api/v1}"

# zt_require — verify curl + jq are present. Returns non-zero with a clear message.
zt_require() {
  command -v curl >/dev/null 2>&1 || { echo "zt-api: 'curl' is required but not found" >&2; return 1; }
  command -v jq   >/dev/null 2>&1 || { echo "zt-api: 'jq' is required but not found"   >&2; return 1; }
}

# _zt_curl METHOD PATH [json-body]
# Internal. Prints the response body to stdout; accepts HTTP 2xx only.
_zt_curl() {
  local method="$1" path="$2" body="${3:-}"
  local token="${ZEROTIER_API_TOKEN:-}"
  [ -n "$token" ] || { echo "zt-api: ZEROTIER_API_TOKEN is not set" >&2; return 1; }

  local url="${ZT_API_BASE}${path}" tmp code curl_rc=0
  tmp="$(mktemp)"
  if [ -n "$body" ]; then
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      --connect-timeout 10 --max-time 60 --retry 3 --retry-all-errors \
      -H "Authorization: token ${token}" \
      -H "Content-Type: application/json" \
      -d "$body")" || curl_rc=$?
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "$url" \
      --connect-timeout 10 --max-time 60 --retry 3 --retry-all-errors \
      -H "Authorization: token ${token}")" || curl_rc=$?
  fi
  cat "$tmp"
  rm -f "$tmp"

  if [ "$curl_rc" -ne 0 ]; then
    echo "zt-api: ${method} ${path} -> curl exit ${curl_rc}" >&2
    return 1
  fi
  if [ -z "${code}" ] || [ "${code}" -lt 200 ] 2>/dev/null || [ "${code}" -ge 300 ] 2>/dev/null; then
    echo "zt-api: ${method} ${path} -> HTTP ${code:-000}" >&2
    return 1
  fi
}

_zt_validate_ids() {
  [[ "$1" =~ ^[0-9A-Fa-f]{16}$ ]] ||
    { echo "zt-api: invalid network ID: $1" >&2; return 1; }
  [[ "$2" =~ ^[0-9A-Fa-f]{10}$ ]] ||
    { echo "zt-api: invalid node ID: $2" >&2; return 1; }
}

# zt_get_member NETWORK_ID NODE_ID  ->  member JSON on stdout
zt_get_member() {
  _zt_validate_ids "$1" "$2" || return 1
  _zt_curl GET "/network/$1/member/$2"
}

# zt_authorize_member NETWORK_ID NODE_ID NAME [OVERLAY_IP]
# Authorizes the member and (optionally) pins a fixed overlay IP. Idempotent.
zt_authorize_member() {
  local net="$1" node="$2" name="$3" ip="${4:-}" cfg payload
  _zt_validate_ids "$net" "$node" || return 1
  if [ -n "$ip" ]; then
    cfg="$(jq -nc --arg ip "$ip" '{authorized:true, ipAssignments:[$ip]}')"
  else
    cfg="$(jq -nc '{authorized:true}')"
  fi
  payload="$(jq -nc --arg name "$name" --argjson config "$cfg" '{name:$name, config:$config}')"
  _zt_curl POST "/network/$net/member/$node" "$payload" >/dev/null
}

# zt_delete_member NETWORK_ID NODE_ID
zt_delete_member() {
  _zt_validate_ids "$1" "$2" || return 1
  _zt_curl DELETE "/network/$1/member/$2" >/dev/null
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
# Polls until the member is online, authorized, and has an overlay IP.
zt_wait_member_online() {
  local net="$1" node="$2" timeout="${3:-90}" waited=0 j auth online ip
  while [ "$waited" -lt "$timeout" ]; do
    j="$(zt_get_member "$net" "$node" 2>/dev/null || true)"
    auth="$(printf '%s' "$j" | jq -r '.config.authorized // false' 2>/dev/null || echo false)"
    online="$(printf '%s' "$j" | jq -r '.online // false' 2>/dev/null || echo false)"
    ip="$(printf '%s' "$j" | jq -r '.config.ipAssignments[0] // empty' 2>/dev/null || true)"
    if [ "$auth" = "true" ] && [ "$online" = "true" ] && [ -n "$ip" ]; then
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
