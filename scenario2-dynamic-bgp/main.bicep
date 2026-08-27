// ===========================================================================
// Scenario 2 - On-Premises to Azure Hub & Spoke (DYNAMIC routing / BGP)
// ---------------------------------------------------------------------------
// Same topology as Scenario 1, but routing is learned dynamically instead of
// via static UDRs:
//
//   onprem-nva --BGP over ZeroTier--> hub-nva --BGP--> Azure Route Server
//                                                        |
//                                          injects routes into hub + spokes
//
//   * hub-nva runs FRR and peers with BOTH Route Server IPs and the onprem-nva.
//   * Route Server advertises the Azure VNet prefixes to hub-nva and injects
//     on-prem prefixes (learned from hub-nva) into the hub + peered spokes.
//   * Gateway transit on the hub<->spoke peerings lets spokes use the Route
//     Server, so no static site-prefix UDRs are needed on the Azure side.
//     Default-route UDRs provide explicit Internet egress through hub-nva.
//   * The on-prem side has no Route Server, so onprem keeps a static UDR that
//     points RFC1918 at its local NVA (the "customer edge").
//
// Infrastructure only. ZeroTier + FRR/BGP are configured post-deploy by
// deploy.sh (see ./frr for the FRR templates).
// ===========================================================================

targetScope = 'resourceGroup'

// --------------------------- Parameters ------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('VM size for all VMs and NVAs.')
@minLength(1)
param vmSize string = 'Standard_DS1_v2'

@description('Admin username for all VMs.')
@minLength(1)
param adminUsername string

@description('SSH public key for the admin account on all VMs.')
@minLength(20)
param sshPublicKey string

@description('Your public IP (CIDR or single IP) allowed to SSH into the lab.')
@minLength(7)
param allowedSshSourceIp string

@description('Base64-encoded cloud-init for the NVAs (scripts/cloud-init-nva.yaml).')
@secure()
param nvaCloudInit string

@description('Base64-encoded cloud-init for the workload VMs (scripts/cloud-init-tools.yaml).')
@secure()
param toolsCloudInit string

@description('BGP ASN for the hub NVA (peers the Route Server). Must not be 65515.')
@minValue(1)
@maxValue(4294967294)
param hubNvaAsn int = 65001

@description('Resource tags applied to every resource.')
param tags object = {
  lab: 'azure-zt-lab'
  scenario: 'scenario2-dynamic-bgp'
}

// --------------------------- Variables -------------------------------------

// Static private IPs for the NVAs (first usable host in each /27 nvasubnet).
var hubNvaIp = '10.0.0.36'
var onpremNvaIp = '192.168.100.36'

var rfc1918Prefixes = [
  '10.0.0.0/8'
  '172.16.0.0/12'
  '192.168.0.0/16'
]

// On-prem edge still routes statically to its own NVA (no Route Server on-prem).
var onpremNvaRoutes = [
  { name: 'to-10-net', prefix: '10.0.0.0/8', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
  { name: 'to-172-net', prefix: '172.16.0.0/12', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
  { name: 'to-192-net', prefix: '192.168.0.0/16', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
  { name: 'internet-egress', prefix: '0.0.0.0/0', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
]

// Azure site prefixes remain dynamic; this UDR handles Internet egress only.
var hubNvaEgressRoute = [
  { name: 'internet-egress', prefix: '0.0.0.0/0', nextHopType: 'VirtualAppliance', nextHopIp: hubNvaIp }
]

// --------------------------- Security Groups -------------------------------

module workloadNsg '../modules/nsg.bicep' = {
  name: 'workload-nsg'
  params: {
    name: 'default-nsg'
    location: location
    tags: tags
    securityRules: []
  }
}

module nvaNsg '../modules/nsg.bicep' = {
  name: 'nva-nsg'
  params: {
    name: 'nva-nsg'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'allow-rfc1918-in'
        properties: {
          priority: 310
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefixes: rfc1918Prefixes
          sourcePortRange: '*'
          destinationAddressPrefixes: rfc1918Prefixes
          destinationPortRange: '*'
        }
      }
      {
        name: 'allow-rfc1918-out'
        properties: {
          priority: 320
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefixes: rfc1918Prefixes
          sourcePortRange: '*'
          destinationAddressPrefixes: rfc1918Prefixes
          destinationPortRange: '*'
        }
      }
      {
        name: 'allow-rfc1918-internet-forward'
        properties: {
          priority: 325
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefixes: rfc1918Prefixes
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }
      {
        name: 'allow-ssh-inbound'
        properties: {
          priority: 330
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedSshSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// --------------------------- Route Tables (on-prem only) -------------------

module onpremUdr '../modules/route-table.bicep' = {
  name: 'onprem-udr'
  params: {
    name: 'onprem-udr'
    location: location
    tags: tags
    routes: onpremNvaRoutes
  }
}

module hubEgressUdr '../modules/route-table.bicep' = {
  name: 'hub-egress-udr'
  params: {
    name: 'hub-egress-udr'
    location: location
    tags: tags
    routes: hubNvaEgressRoute
  }
}

module spoke1EgressUdr '../modules/route-table.bicep' = {
  name: 'spoke1-egress-udr'
  params: {
    name: 'spoke1-egress-udr'
    location: location
    tags: tags
    routes: hubNvaEgressRoute
  }
}

module spoke2EgressUdr '../modules/route-table.bicep' = {
  name: 'spoke2-egress-udr'
  params: {
    name: 'spoke2-egress-udr'
    location: location
    tags: tags
    routes: hubNvaEgressRoute
  }
}

// --------------------------- Virtual Networks ------------------------------
// hub-vnet gains a dedicated RouteServerSubnet. Azure site routes are learned
// dynamically; the attached UDRs contain only explicit NVA egress defaults.

module hubVnet '../modules/vnet.bicep' = {
  name: 'hub-vnet'
  params: {
    name: 'hub-vnet'
    location: location
    tags: tags
    addressPrefixes: [ '10.0.0.0/24' ]
    subnets: [
      { name: 'subnet1', prefix: '10.0.0.0/27', nsgId: workloadNsg.outputs.id, routeTableId: hubEgressUdr.outputs.id }
      { name: 'nvasubnet', prefix: '10.0.0.32/27', nsgId: nvaNsg.outputs.id }
      { name: 'RouteServerSubnet', prefix: '10.0.0.64/27' }
    ]
  }
}

module spoke1Vnet '../modules/vnet.bicep' = {
  name: 'spoke1-vnet'
  params: {
    name: 'spoke1-vnet'
    location: location
    tags: tags
    addressPrefixes: [ '10.0.1.0/24' ]
    subnets: [
      { name: 'subnet1', prefix: '10.0.1.0/27', nsgId: workloadNsg.outputs.id, routeTableId: spoke1EgressUdr.outputs.id }
    ]
  }
}

module spoke2Vnet '../modules/vnet.bicep' = {
  name: 'spoke2-vnet'
  params: {
    name: 'spoke2-vnet'
    location: location
    tags: tags
    addressPrefixes: [ '10.0.2.0/24' ]
    subnets: [
      { name: 'subnet1', prefix: '10.0.2.0/27', nsgId: workloadNsg.outputs.id, routeTableId: spoke2EgressUdr.outputs.id }
    ]
  }
}

module onpremVnet '../modules/vnet.bicep' = {
  name: 'onprem-vnet'
  params: {
    name: 'onprem-vnet'
    location: location
    tags: tags
    addressPrefixes: [ '192.168.100.0/24' ]
    subnets: [
      { name: 'subnet1', prefix: '192.168.100.0/27', nsgId: workloadNsg.outputs.id, routeTableId: onpremUdr.outputs.id }
      { name: 'nvasubnet', prefix: '192.168.100.32/27', nsgId: nvaNsg.outputs.id }
    ]
  }
}

// --------------------------- Peerings (with gateway transit) ---------------
// Hub side allows gateway transit; spoke side uses remote gateways so the
// Route Server in the hub propagates learned routes into the spokes.

module peerSpoke1ToHub '../modules/vnet-peering.bicep' = {
  name: 'spoke1-to-hub'
  params: {
    localVnetName: spoke1Vnet.outputs.name
    peeringName: 'spoke1-to-hub'
    remoteVnetId: hubVnet.outputs.id
    useRemoteGateways: true
  }
  // The hub peering must already advertise gateway transit, and the Route
  // Server (the "gateway") must exist, before a spoke can use remote gateways.
  dependsOn: [
    routeServer
    peerHubToSpoke1
  ]
}

module peerHubToSpoke1 '../modules/vnet-peering.bicep' = {
  name: 'hub-to-spoke1'
  params: {
    localVnetName: hubVnet.outputs.name
    peeringName: 'hub-to-spoke1'
    remoteVnetId: spoke1Vnet.outputs.id
    allowGatewayTransit: true
  }
}

module peerSpoke2ToHub '../modules/vnet-peering.bicep' = {
  name: 'spoke2-to-hub'
  params: {
    localVnetName: spoke2Vnet.outputs.name
    peeringName: 'spoke2-to-hub'
    remoteVnetId: hubVnet.outputs.id
    useRemoteGateways: true
  }
  dependsOn: [
    routeServer
    peerHubToSpoke2
  ]
}

module peerHubToSpoke2 '../modules/vnet-peering.bicep' = {
  name: 'hub-to-spoke2'
  params: {
    localVnetName: hubVnet.outputs.name
    peeringName: 'hub-to-spoke2'
    remoteVnetId: spoke2Vnet.outputs.id
    allowGatewayTransit: true
  }
}

// --------------------------- Azure Route Server ----------------------------

module routeServer '../modules/route-server.bicep' = {
  name: 'route-server'
  params: {
    name: 'hub-route-server'
    location: location
    tags: tags
    routeServerSubnetId: hubVnet.outputs.subnetIds.RouteServerSubnet
    bgpPeers: [
      {
        name: 'hub-nva'
        peerAsn: hubNvaAsn
        peerIp: hubNvaIp
      }
    ]
  }
}

// --------------------------- Workload VMs ----------------------------------

module hubVm '../modules/linux-vm.bicep' = {
  name: 'hub-vm1'
  params: {
    name: 'hub-vm1'
    location: location
    vmSize: vmSize
    tags: tags
    subnetId: hubVnet.outputs.subnetIds.subnet1
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    customData: toolsCloudInit
    createPublicIp: false
  }
  dependsOn: [
    hubNva
  ]
}

module spoke1Vm '../modules/linux-vm.bicep' = {
  name: 'spoke1-vm1'
  params: {
    name: 'spoke1-vm1'
    location: location
    vmSize: vmSize
    tags: tags
    subnetId: spoke1Vnet.outputs.subnetIds.subnet1
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    customData: toolsCloudInit
    createPublicIp: false
  }
  dependsOn: [
    hubNva
    peerSpoke1ToHub
  ]
}

module spoke2Vm '../modules/linux-vm.bicep' = {
  name: 'spoke2-vm1'
  params: {
    name: 'spoke2-vm1'
    location: location
    vmSize: vmSize
    tags: tags
    subnetId: spoke2Vnet.outputs.subnetIds.subnet1
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    customData: toolsCloudInit
    createPublicIp: false
  }
  dependsOn: [
    hubNva
    peerSpoke2ToHub
  ]
}

module onpremVm '../modules/linux-vm.bicep' = {
  name: 'onprem-vm1'
  params: {
    name: 'onprem-vm1'
    location: location
    vmSize: vmSize
    tags: tags
    subnetId: onpremVnet.outputs.subnetIds.subnet1
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    customData: toolsCloudInit
    createPublicIp: false
  }
  dependsOn: [
    onpremNva
  ]
}

// --------------------------- NVAs ------------------------------------------

module hubNva '../modules/linux-vm.bicep' = {
  name: 'hub-nva'
  params: {
    name: 'hub-nva'
    location: location
    vmSize: vmSize
    tags: tags
    subnetId: hubVnet.outputs.subnetIds.nvasubnet
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    customData: nvaCloudInit
    enableIpForwarding: true
    staticPrivateIp: hubNvaIp
  }
}

module onpremNva '../modules/linux-vm.bicep' = {
  name: 'onprem-nva'
  params: {
    name: 'onprem-nva'
    location: location
    vmSize: vmSize
    tags: tags
    subnetId: onpremVnet.outputs.subnetIds.nvasubnet
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    customData: nvaCloudInit
    enableIpForwarding: true
    staticPrivateIp: onpremNvaIp
  }
}

// --------------------------- Outputs ---------------------------------------

output hubNvaPublicIp string = hubNva.outputs.publicIp
output hubNvaPrivateIp string = hubNva.outputs.privateIp
output onpremNvaPublicIp string = onpremNva.outputs.publicIp
output onpremNvaPrivateIp string = onpremNva.outputs.privateIp

@description('The two Route Server BGP IPs the hub NVA must peer with.')
output routeServerIps array = routeServer.outputs.routeServerIps

@description('Route Server ASN (always 65515).')
output routeServerAsn int = routeServer.outputs.routeServerAsn

output hubVmPrivateIp string = hubVm.outputs.privateIp
output spoke1VmPrivateIp string = spoke1Vm.outputs.privateIp
output spoke2VmPrivateIp string = spoke2Vm.outputs.privateIp
output onpremVmPrivateIp string = onpremVm.outputs.privateIp
