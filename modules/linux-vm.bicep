// ---------------------------------------------------------------------------
// Linux VM (Ubuntu 22.04, SSH-key authentication)
// One reusable module for both workload VMs and NVAs. Set enableIpForwarding
// and a staticPrivateIp for NVAs; leave defaults for plain workload VMs.
// ---------------------------------------------------------------------------

@description('Name of the virtual machine.')
@minLength(1)
param name string

@description('Azure region for the VM and its network resources.')
param location string = resourceGroup().location

@description('VM size / SKU.')
param vmSize string = 'Standard_DS1_v2'

@description('Resource ID of the subnet to attach the NIC to.')
param subnetId string

@description('Admin username for the VM.')
@minLength(1)
param adminUsername string

@description('SSH public key used for the admin account.')
@minLength(20)
param sshPublicKey string

@description('Base64-encoded cloud-init / custom data. Leave empty for none.')
@secure()
param customData string = ''

@description('Enable IP forwarding on the NIC (required for NVAs).')
param enableIpForwarding bool = false

@description('Static private IP for the NIC. Leave empty for dynamic allocation.')
param staticPrivateIp string = ''

@description('Create and attach a Standard public IP.')
param createPublicIp bool = true

@description('Resource tags.')
param tags object = {}

var hasStaticIp = !empty(staticPrivateIp)
var hasCustomData = !empty(customData)

resource publicIp 'Microsoft.Network/publicIPAddresses@2025-05-01' = if (createPublicIp) {
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

resource nic 'Microsoft.Network/networkInterfaces@2025-05-01' = {
  name: '${name}-nic'
  location: location
  tags: tags
  properties: {
    enableIPForwarding: enableIpForwarding
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: hasStaticIp ? 'Static' : 'Dynamic'
          privateIPAddress: hasStaticIp ? staticPrivateIp : null
          publicIPAddress: createPublicIp ? {
            id: publicIp.id
          } : null
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      customData: hasCustomData ? customData : null
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

@description('Name of the VM.')
output name string = vm.name

@description('Private IP address of the VM NIC.')
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress

@description('Public IP address (empty when createPublicIp is false).')
output publicIp string = createPublicIp ? (publicIp.?properties.ipAddress ?? '') : ''
