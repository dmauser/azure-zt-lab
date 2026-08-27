// ---------------------------------------------------------------------------
// Azure Route Server
// A Route Server is a Microsoft.Network/virtualHubs with sku=Standard and NO
// virtualWan association. It exchanges routes with NVAs over BGP and injects
// them into the VNet (and peered spokes via gateway transit).
//
// Requirements:
//   * A dedicated subnet named EXACTLY "RouteServerSubnet" (min /27) in the hub.
//   * A Standard, Static public IP for the Route Server data plane.
//   * Route Server's own ASN is fixed at 65515; peers must use a different ASN.
// ---------------------------------------------------------------------------

@description('Name of the Route Server.')
@minLength(1)
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Resource ID of the dedicated "RouteServerSubnet".')
param routeServerSubnetId string

@sealed()
type BgpPeer = {
  name: string
  peerAsn: int
  peerIp: string
}

@description('BGP peers (NVAs). peerAsn must not be 65515.')
param bgpPeers BgpPeer[] = []

@description('Allow branch-to-branch route exchange (routes learned from one peer are advertised to others / the VNet).')
param allowBranchToBranchTraffic bool = true

@description('Resource tags.')
param tags object = {}

resource publicIp 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: '${name}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource routeServer 'Microsoft.Network/virtualHubs@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: 'Standard'
    allowBranchToBranchTraffic: allowBranchToBranchTraffic
  }
}

resource ipConfig 'Microsoft.Network/virtualHubs/ipConfigurations@2025-05-01' = {
  parent: routeServer
  name: 'ipconfig1'
  properties: {
    subnet: {
      id: routeServerSubnetId
    }
    publicIPAddress: {
      id: publicIp.id
    }
  }
}

// One BGP connection per peer. These depend on the ipConfiguration because the
// Route Server data plane must exist before peers can be attached, and the ARM
// provider does not allow parallel child writes on a virtualHub.
@batchSize(1)
resource bgpConnections 'Microsoft.Network/virtualHubs/bgpConnections@2025-05-01' = [
  for peer in bgpPeers: {
    parent: routeServer
    name: peer.name
    properties: {
      peerAsn: peer.peerAsn
      peerIp: peer.peerIp
    }
    dependsOn: [
      ipConfig
    ]
  }
]

module state './route-server-state.bicep' = {
  name: 'route-server-state'
  params: {
    routeServerName: routeServer.name
  }
  dependsOn: [
    bgpConnections
  ]
}

@description('Resource ID of the Route Server.')
output id string = routeServer.id

@description('Route Server BGP peer IPs (the two addresses to peer your NVA against).')
output routeServerIps array = state.outputs.routeServerIps

@description('Route Server ASN (always 65515).')
output routeServerAsn int = state.outputs.routeServerAsn
