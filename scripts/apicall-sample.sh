#!/usr/bin/env bash
# ===========================================================================
# scripts/apicall-sample.sh — minimal ZeroTier Central REST API example
# ---------------------------------------------------------------------------
# Authorizes a single member and pins a fixed overlay IP via a raw curl call.
# For the reusable helper the labs actually use, see scripts/zt-api.sh.
#
# Token guidance: https://docs.zerotier.com/tokens/
# ===========================================================================
set -euo pipefail

ZEROTIER_API_TOKEN="${ZEROTIER_API_TOKEN:-YOUR_API_TOKEN}"
NETWORK_ID="${NETWORK_ID:-YOUR_NETWORK_ID}"      # 16-hex ZeroTier network ID
NODE_ID="${NODE_ID:-YOUR_NODE_ID}"               # 10-hex member ID (zerotier-cli info -> field 3)
CUSTOM_IP="${CUSTOM_IP:-172.27.0.10}"            # must be inside the network's managed route
DEVICE_NAME="${DEVICE_NAME:-my-device}"

API_BASE="https://api.zerotier.com/api/v1"
JSON_PAYLOAD=$(cat <<JSON
{
  "name": "${DEVICE_NAME}",
  "config": {
    "authorized": true,
    "ipAssignments": ["${CUSTOM_IP}"]
  }
}
JSON
)

# A single POST both authorizes the member and applies the pinned IP.
curl -sS -X POST "${API_BASE}/network/${NETWORK_ID}/member/${NODE_ID}" \
     -H "Authorization: token ${ZEROTIER_API_TOKEN}" \
     -H "Content-Type: application/json" \
     -d "${JSON_PAYLOAD}"