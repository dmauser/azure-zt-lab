// ---------------------------------------------------------------------------
// Network Security Group
// Reusable NSG module. The caller supplies the full list of security rules so
// the same module serves both the "workload" NSG (allow SSH from your IP) and
// the "NVA" NSG (allow RFC1918 east-west + SSH).
// ---------------------------------------------------------------------------

@description('Name of the network security group.')
param name string

@description('Azure region for the NSG.')
param location string = resourceGroup().location

@description('Security rules to apply. Each item is a full NSG securityRule object.')
param securityRules array = []

@description('Resource tags.')
param tags object = {}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
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
