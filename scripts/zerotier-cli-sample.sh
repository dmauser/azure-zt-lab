#!/bin/bash

# Replace with your network ID, desired device name, and desired IP address
NETWORK_ID="YOUR_NETWORK_ID"
DEVICE_NAME="Your_Device_Name"
CUSTOM_IP="192.168.1.100"

# Join ZeroTier network
zerotier-cli join "$NETWORK_ID"

# Wait for a moment to ensure the network connection is established
sleep 5

# Retrieve device ID based on device name
device_id=$(zerotier-cli listpeers | jq -r '.[] | select(.name == "'"$DEVICE_NAME"'") | .address')

# Modify device configuration
JSON_PAYLOAD='{
  "name": "'"$DEVICE_NAME"'",
  "config": {
    "ipAssignments": ["'"$CUSTOM_IP"'"]
  }
}'
zerotier-cli orbit "$device_id" "$JSON_PAYLOAD"

echo "Device ID: $device_id"
echo "Device name and IP modified"
