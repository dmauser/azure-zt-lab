targetScope = 'resourceGroup'

@description('Name of the provisioned Azure Route Server.')
param routeServerName string

resource routeServer 'Microsoft.Network/virtualHubs@2025-05-01' existing = {
  name: routeServerName
}

@description('Route Server BGP peer IPs read after its IP configuration is provisioned.')
output routeServerIps array = routeServer.properties.virtualRouterIps

@description('Route Server ASN.')
output routeServerAsn int = routeServer.properties.virtualRouterAsn
