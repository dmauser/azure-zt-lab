#!/bin/bash

ZEROTIER_API_TOKEN="YOUR_API_TOKEN"
NETWORK_ID="YOUR_NETWORK_ID"
DEVICE_ID="YOUR_DEVICE_ID"
CUSTOM_IP="192.168.1.100"
DEVICE_NAME="Your_Device_Name"   # Replace with the actual device name
API_ENDPOINT="https://my.zerotier.com/api/network/$NETWORK_ID/member/$DEVICE_ID"
JSON_PAYLOAD='{
  "config": {
    "ipAssignments": ["'"$CUSTOM_IP"'"]
  },
  "name": "'"$DEVICE_NAME"'"
}'

# Send the API request
curl -X POST "$API_ENDPOINT" \
     -H "Authorization: Bearer $ZEROTIER_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD"
