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
param name string

@description('Azure region for the VNet.')
param location string = resourceGroup().location

@description('Address space (CIDR blocks) for the VNet.')
param addressPrefixes array

@description('''Subnets to create. Each item:
{
  name: string
  prefix: string            // CIDR
  nsgId: string (optional)  // NSG resource ID
  routeTableId: string (optional) // Route Table resource ID
}''')
param subnets array

@description('Resource tags.')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
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
          networkSecurityGroup: contains(s, 'nsgId') && !empty(s.nsgId) ? {
            id: s.nsgId
          } : null
          routeTable: contains(s, 'routeTableId') && !empty(s.routeTableId) ? {
            id: s.routeTableId
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
