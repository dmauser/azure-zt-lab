// ---------------------------------------------------------------------------
// Virtual Network (+ subnets)
// Creates a VNet and its subnets. Each subnet may optionally reference an NSG
// and/or a Route Table by resource ID.
//
// Design note: route tables are wired here by ID only. Because the lab assigns
// STATIC private IPs to the NVAs, the route tables reference those IPs as plain
// strings (not resource references), so there is no circular dependency between
// subnets -> route tables -> NVAs.
// ---------------------------------------------------------------------------

@description('Name of the virtual network.')
@minLength(1)
param name string

@description('Azure region for the VNet.')
param location string = resourceGroup().location

@description('Address space (CIDR blocks) for the VNet.')
param addressPrefixes string[]

@sealed()
type SubnetConfig = {
  name: string
  prefix: string
  nsgId: string?
  routeTableId: string?
}

@description('Subnets to create, with optional NSG and route-table resource IDs.')
param subnets SubnetConfig[]

@description('Resource tags.')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    subnets: [
      for s in subnets: {
        name: s.name
        properties: {
          addressPrefix: s.prefix
          networkSecurityGroup: !empty(s.?nsgId) ? {
            id: s.?nsgId
          } : null
          routeTable: !empty(s.?routeTableId) ? {
            id: s.?routeTableId
          } : null
        }
      }
    ]
  }
}

@description('Resource ID of the VNet.')
output id string = vnet.id

@description('Name of the VNet.')
output name string = vnet.name

@description('Map of subnet name -> subnet resource ID.')
output subnetIds object = reduce(subnets, {}, (cur, next) => union(cur, {
  '${next.name}': resourceId('Microsoft.Network/virtualNetworks/subnets', name, next.name)
}))
