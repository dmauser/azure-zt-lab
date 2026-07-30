// ===========================================================================
// Scenario 1 - On-Premises to Azure Hub & Spoke (STATIC routing)
// ---------------------------------------------------------------------------
// Topology:
//   onprem-vnet (192.168.100.0/24) --[ZeroTier overlay]-- hub-vnet (10.0.0.0/24)
//                                                          |  peering  |  peering
//                                                     spoke1-vnet   spoke2-vnet
//                                                     (10.0.1/24)   (10.0.2/24)
//
//   * hub-nva and onprem-nva build a ZeroTier overlay (configured post-deploy).
//   * Static UDRs steer RFC1918 traffic to the local NVA.
//   * NVAs use STATIC private IPs so the UDRs are deterministic.
//
// This template provisions infrastructure only. ZeroTier install/join is done
// by deploy.sh after the deployment completes.
// ===========================================================================

targetScope = 'resourceGroup'

// --------------------------- Parameters ------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('VM size for all VMs and NVAs.')
param vmSize string = 'Standard_DS1_v2'

@description('Admin username for all VMs.')
param adminUsername string

@description('Admin password for all VMs.')
@secure()
param adminPassword string

@description('Your public IP (CIDR or single IP) allowed to SSH into the lab, e.g. 203.0.113.10.')
param allowedSshSourceIp string

@description('Base64-encoded cloud-init for the NVAs (scripts/cloud-init-nva.yaml).')
@secure()
param nvaCloudInit string

@description('Base64-encoded cloud-init for the workload VMs (scripts/cloud-init-tools.yaml).')
@secure()
param toolsCloudInit string

@description('Resource tags applied to every resource.')
param tags object = {
  lab: 'azure-zt-lab'
  scenario: 'scenario1-static-routing'
}

// --------------------------- Variables -------------------------------------

// Static private IPs for the NVAs (first usable host in each /27 nvasubnet:
// Azure reserves .32-.35, so .36 is the first assignable address).
var hubNvaIp = '10.0.0.36'
var onpremNvaIp = '192.168.100.36'

var rfc1918Prefixes = [
  '10.0.0.0/8'
  '172.16.0.0/12'
  '192.168.0.0/16'
]

// RFC1918 routes pointing at the hub NVA (used by hub + spoke subnets).
var hubNvaRoutes = [
  { name: 'to-10-net', prefix: '10.0.0.0/8', nextHopType: 'VirtualAppliance', nextHopIp: hubNvaIp }
  { name: 'to-172-net', prefix: '172.16.0.0/12', nextHopType: 'VirtualAppliance', nextHopIp: hubNvaIp }
  { name: 'to-192-net', prefix: '192.168.0.0/16', nextHopType: 'VirtualAppliance', nextHopIp: hubNvaIp }
]

// RFC1918 routes pointing at the on-prem NVA.
var onpremNvaRoutes = [
  { name: 'to-10-net', prefix: '10.0.0.0/8', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
  { name: 'to-172-net', prefix: '172.16.0.0/12', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
  { name: 'to-192-net', prefix: '192.168.0.0/16', nextHopType: 'VirtualAppliance', nextHopIp: onpremNvaIp }
]

// --------------------------- Security Groups -------------------------------

module workloadNsg '../modules/nsg.bicep' = {
  name: 'workload-nsg'
  params: {
    name: 'default-nsg'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'allow-ssh-inbound'
        properties: {
          priority: 1000
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

// --------------------------- Route Tables ----------------------------------

module hubUdr '../modules/route-table.bicep' = {
  name: 'hub-udr'
  params: {
    name: 'hub-udr'
    location: location
    tags: tags
    routes: hubNvaRoutes
  }
}

module spoke1Udr '../modules/route-table.bicep' = {
  name: 'spoke1-udr'
  params: {
    name: 'spoke1-udr'
    location: location
    tags: tags
    routes: hubNvaRoutes
  }
}

module spoke2Udr '../modules/route-table.bicep' = {
  name: 'spoke2-udr'
  params: {
    name: 'spoke2-udr'
    location: location
    tags: tags
    routes: hubNvaRoutes
  }
}

module onpremUdr '../modules/route-table.bicep' = {
  name: 'onprem-udr'
  params: {
    name: 'onprem-udr'
    location: location
    tags: tags
    routes: onpremNvaRoutes
  }
}

// --------------------------- Virtual Networks ------------------------------

module hubVnet '../modules/vnet.bicep' = {
  name: 'hub-vnet'
  params: {
    name: 'hub-vnet'
    location: location
    tags: tags
    addressPrefixes: [ '10.0.0.0/24' ]
    subnets: [
      { name: 'subnet1', prefix: '10.0.0.0/27', nsgId: workloadNsg.outputs.id, routeTableId: hubUdr.outputs.id }
      { name: 'nvasubnet', prefix: '10.0.0.32/27', nsgId: nvaNsg.outputs.id }
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
      { name: 'subnet1', prefix: '10.0.1.0/27', nsgId: workloadNsg.outputs.id, routeTableId: spoke1Udr.outputs.id }
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
      { name: 'subnet1', prefix: '10.0.2.0/27', nsgId: workloadNsg.outputs.id, routeTableId: spoke2Udr.outputs.id }
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

// --------------------------- Peerings (hub <-> spokes) ---------------------

module peerSpoke1ToHub '../modules/vnet-peering.bicep' = {
  name: 'spoke1-to-hub'
  params: {
    localVnetName: spoke1Vnet.outputs.name
    peeringName: 'spoke1-to-hub'
    remoteVnetId: hubVnet.outputs.id
  }
}

module peerHubToSpoke1 '../modules/vnet-peering.bicep' = {
  name: 'hub-to-spoke1'
  params: {
    localVnetName: hubVnet.outputs.name
    peeringName: 'hub-to-spoke1'
    remoteVnetId: spoke1Vnet.outputs.id
  }
}

module peerSpoke2ToHub '../modules/vnet-peering.bicep' = {
  name: 'spoke2-to-hub'
  params: {
    localVnetName: spoke2Vnet.outputs.name
    peeringName: 'spoke2-to-hub'
    remoteVnetId: hubVnet.outputs.id
  }
}

module peerHubToSpoke2 '../modules/vnet-peering.bicep' = {
  name: 'hub-to-spoke2'
  params: {
    localVnetName: hubVnet.outputs.name
    peeringName: 'hub-to-spoke2'
    remoteVnetId: spoke2Vnet.outputs.id
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
    adminPassword: adminPassword
    customData: toolsCloudInit
  }
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
    adminPassword: adminPassword
    customData: toolsCloudInit
  }
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
    adminPassword: adminPassword
    customData: toolsCloudInit
  }
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
    adminPassword: adminPassword
    customData: toolsCloudInit
  }
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
    adminPassword: adminPassword
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
    adminPassword: adminPassword
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

output hubVmPublicIp string = hubVm.outputs.publicIp
output spoke1VmPublicIp string = spoke1Vm.outputs.publicIp
output spoke2VmPublicIp string = spoke2Vm.outputs.publicIp
output onpremVmPublicIp string = onpremVm.outputs.publicIp
