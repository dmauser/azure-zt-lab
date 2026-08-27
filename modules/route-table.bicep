// ---------------------------------------------------------------------------
// Route Table (User Defined Routes)
// Used by Scenario 1 (static routing) to steer RFC1918 traffic at the NVA.
// ---------------------------------------------------------------------------

@description('Name of the route table.')
@minLength(1)
param name string

@description('Azure region for the route table.')
param location string = resourceGroup().location

@sealed()
type RouteConfig = {
  name: string
  prefix: string
  nextHopType: 'VirtualAppliance' | 'Internet' | 'VnetLocal' | 'None'
  nextHopIp: string?
}

@description('Routes to create.')
param routes RouteConfig[] = []

@description('Disable BGP route propagation on the subnets this table is attached to.')
param disableBgpRoutePropagation bool = false

@description('Resource tags.')
param tags object = {}

resource routeTable 'Microsoft.Network/routeTables@2025-05-01' = {
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
          nextHopIpAddress: !empty(r.?nextHopIp) ? r.?nextHopIp : null
        }
      }
    ]
  }
}

@description('Resource ID of the route table.')
output id string = routeTable.id

@description('Name of the route table.')
output name string = routeTable.name
