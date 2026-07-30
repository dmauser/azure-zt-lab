// ---------------------------------------------------------------------------
// Route Table (User Defined Routes)
// Used by Scenario 1 (static routing) to steer RFC1918 traffic at the NVA.
// ---------------------------------------------------------------------------

@description('Name of the route table.')
param name string

@description('Azure region for the route table.')
param location string = resourceGroup().location

@description('''Routes to create. Each item:
{
  name: string
  prefix: string        // destination CIDR
  nextHopType: string   // e.g. VirtualAppliance, Internet, VnetLocal
  nextHopIp: string (optional) // required when nextHopType == VirtualAppliance
}''')
param routes array = []

@description('Disable BGP route propagation on the subnets this table is attached to.')
param disableBgpRoutePropagation bool = false

@description('Resource tags.')
param tags object = {}

resource routeTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: disableBgpRoutePropagation
    routes: [
      for r in routes: {
        name: r.name
        properties: {
          addressPrefix: r.prefix
          nextHopType: r.nextHopType
          nextHopIpAddress: contains(r, 'nextHopIp') && !empty(r.nextHopIp) ? r.nextHopIp : null
        }
      }
    ]
  }
}

@description('Resource ID of the route table.')
output id string = routeTable.id

@description('Name of the route table.')
output name string = routeTable.name
