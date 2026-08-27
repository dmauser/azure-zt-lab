// ---------------------------------------------------------------------------
// Network Security Group
// Reusable NSG module. The caller supplies the full list of security rules so
// the same module serves private workload NSGs and NVA forwarding/SSH rules.
// ---------------------------------------------------------------------------

@description('Name of the network security group.')
@minLength(1)
param name string

@description('Azure region for the NSG.')
param location string = resourceGroup().location

@sealed()
type SecurityRuleConfig = {
  name: string
  properties: {
    priority: int
    direction: 'Inbound' | 'Outbound'
    access: 'Allow' | 'Deny'
    protocol: '*' | 'Tcp' | 'Udp' | 'Icmp' | 'Esp' | 'Ah'
    sourceAddressPrefix: string?
    sourceAddressPrefixes: string[]?
    sourcePortRange: string?
    sourcePortRanges: string[]?
    destinationAddressPrefix: string?
    destinationAddressPrefixes: string[]?
    destinationPortRange: string?
    destinationPortRanges: string[]?
  }
}

@description('Security rules to apply.')
param securityRules SecurityRuleConfig[] = []

@description('Resource tags.')
param tags object = {}

resource nsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    securityRules: securityRules
  }
}

@description('Resource ID of the NSG.')
output id string = nsg.id

@description('Name of the NSG.')
output name string = nsg.name
