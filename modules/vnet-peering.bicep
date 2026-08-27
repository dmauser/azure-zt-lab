// ---------------------------------------------------------------------------
// VNet Peering (one direction)
// Create both directions by instantiating this module twice.
// ---------------------------------------------------------------------------

@description('Name of the local VNet that owns this peering.')
@minLength(1)
param localVnetName string

@description('Name for the peering resource.')
@minLength(1)
param peeringName string

@description('Resource ID of the remote VNet.')
param remoteVnetId string

@description('Allow traffic from the remote VNet.')
param allowVirtualNetworkAccess bool = true

@description('Allow forwarded traffic from the remote VNet.')
param allowForwardedTraffic bool = true

@description('Allow gateway/Route Server transit for the remote VNet (set on the hub side).')
param allowGatewayTransit bool = false

@description('Use the remote VNet gateway/Route Server (set on the spoke side).')
param useRemoteGateways bool = false

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-05-01' = {
  name: '${localVnetName}/${peeringName}'
  properties: {
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
  }
}

@description('Resource ID of the peering.')
output id string = peering.id
