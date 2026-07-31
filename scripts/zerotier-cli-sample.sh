#!/usr/bin/env bash
# ===========================================================================
# scripts/zerotier-cli-sample.sh — join a network, then authorize via the API
# ---------------------------------------------------------------------------
# Joining a network from the CLI leaves the member UNAUTHORIZED. Membership is
# a controller-side decision, so it must be granted with the Central REST API
# (or in the portal) — there is no zerotier-cli command that self-authorizes.
#
# This sample joins, reads the local node ID, then authorizes + pins an IP.
# Requires: curl, jq, and a ZeroTier Central API token.
# ===========================================================================
set -euo pipefail

NETWORK_ID="${NETWORK_ID:-YOUR_NETWORK_ID}"
DEVICE_NAME="${DEVICE_NAME:-my-device}"
CUSTOM_IP="${CUSTOM_IP:-172.27.0.10}"            # must be inside the network's managed route
ZEROTIER_API_TOKEN="${ZEROTIER_API_TOKEN:?set your ZeroTier API token}"

API_BASE="https://api.zerotier.com/api/v1"

# 1. Join the network (still unauthorized at this point).
sudo zerotier-cli join "${NETWORK_ID}"
sleep 5

# 2. This node ID is the member ID the controller knows us by.
NODE_ID="$(sudo zerotier-cli info | awk "{print \$3}")"
echo "Local node ID: ${NODE_ID}"

# 3. Authorize this member and pin its overlay IP via the REST API.
curl -sS -X POST "${API_BASE}/network/${NETWORK_ID}/member/${NODE_ID}" \
     -H "Authorization: token ${ZEROTIER_API_TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"name\":\"${DEVICE_NAME}\",\"config\":{\"authorized\":true,\"ipAssignments\":[\"${CUSTOM_IP}\"]}}"

echo
echo "Authorized ${DEVICE_NAME} (${NODE_ID}) with overlay IP ${CUSTOM_IP}"