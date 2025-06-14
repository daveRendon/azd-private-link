@description('Username for the Virtual Machine')
param vmAdminUsername string

@description('Password for the Virtual Machine. The password must be at least 12 characters long and have lower case, upper characters, digit and a special character (Regex match)')
@secure()
param vmAdminPassword string


@description('The size of the VM')
param vmSize string = 'Standard_D2_v3'

@description('Location for all resources.')
param location string = resourceGroup().location
@description('Number of VMs')
param vmCount int = 2

var prefix = 'azinsider'
var vnetName = 'NetworkB-PrivateLink'
var vnetConsumerName = 'NetworkA-PrivateEndpoint'
var vnetAddressPrefix = '10.0.0.0/16'
var frontendSubnetPrefix = '10.0.2.0/24'
var frontendSubnetName = 'frontendSubnet'
var backendSubnetPrefix = '10.0.1.0/24'
var backendSubnetName = 'backendSubnet'
var consumerSubnetPrefix = '10.0.1.0/24'
var consumerSubnetName = 'myPESubnet'
var loadbalancerName = 'myILB'
var backendPoolName = 'myBackEndPool'
var loadBalancerFrontEndIpConfigurationName = 'myFrontEnd'
var healthProbeName = 'myHealthProbe'
var privateEndpointName = 'myPrivateEndpoint'
var vmName = 'myVM'
var networkInterfaceName = '${vmName}-nic'
var vmConsumerName = 'VMConsumer'
var publicIpAddressConsumerName = '${vmConsumerName}PublicIP'
var networkInterfaceConsumerName = '${vmConsumerName}-nic'
var osDiskType = 'StandardSSD_LRS'
var privatelinkServiceName = 'myPLS'
var loadbalancerId = loadbalancer.id


resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: frontendSubnetName
        properties: {
          addressPrefix: frontendSubnetPrefix
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: backendSubnetName
        properties: {
          addressPrefix: backendSubnetPrefix
        }
      }
    ]
  }
}

resource loadbalancer 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: loadbalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  tags: {
    'azd-service-name': 'web'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: loadBalancerFrontEndIpConfigurationName
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, frontendSubnetName)
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
      }
    ]
    inboundNatRules: [
      
    ]
    loadBalancingRules: [
      {
        name: 'myHTTPRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadbalancerName, loadBalancerFrontEndIpConfigurationName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadbalancerName, backendPoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadbalancerName, healthProbeName)
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 15
        }
      }
    ]
    probes: [
      {
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
        name: healthProbeName
      }
    ]
  }
  dependsOn: [
    vnet
  ]
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = [for i in range(0, vmCount): {
  name: '${networkInterfaceName}${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, backendSubnetName)
          }
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadbalancerName, backendPoolName)
            }
          ]
          
        }
      }
    ]
  }
  dependsOn: [
    loadbalancer
  ]
}]

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = [for i in range(0, vmCount): {
  name: '${vmName}${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${vmName}${i}'
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}${i}OsDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
        id: networkInterface[i].id
        }
      ]
    }
  }
} ] 

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = [for i in range(0, vmCount): {
  name: '${vmName}${i}${'installcustomscript'}'
  parent: vm[i]
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: 'powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools && powershell.exe remove-item "C:\\inetpub\\wwwroot\\iisstart.htm" && powershell.exe Add-Content -Path "C:\\inetpub\\wwwroot\\iisstart.htm" -Value $($env:computername)'
    }
  }
}]

resource privatelinkService 'Microsoft.Network/privateLinkServices@2021-05-01' = {
  name: privatelinkServiceName
  location: location
  properties: {
    enableProxyProtocol: false
    loadBalancerFrontendIpConfigurations: [
      {
        id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadbalancerName, loadBalancerFrontEndIpConfigurationName)
      }
    ]
    ipConfigurations: [
      {
        name: 'snet-provider-default-1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: reference(loadbalancerId, '2019-06-01').frontendIPConfigurations[0].properties.subnet.id
          }
          primary: false
        }
      }
    ]
  }
}

resource vnetConsumer 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetConsumerName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: consumerSubnetName
        properties: {
          addressPrefix: consumerSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource publicIpAddressConsumer 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: publicIpAddressConsumerName
  location: location
  tags: {
    displayName: publicIpAddressConsumerName
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: toLower(vmConsumerName)
    }
  }
}

resource networkInterfaceConsumer 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: networkInterfaceConsumerName
  location: location
  tags: {
    displayName: networkInterfaceConsumerName
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpAddressConsumer.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetConsumerName, consumerSubnetName)
          }
        }
      }
    ]
  }
  dependsOn: [
    vnetConsumer
  ]
}

resource vmConsumer 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmConsumerName
  location: location
  tags: {
    displayName: vmConsumerName
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmConsumerName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: '${vmConsumerName}OsDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaceConsumer.id
        }
      ]
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetConsumerName, consumerSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: privatelinkService.id
        }
      }
    ]
  }
  dependsOn: [
    vnetConsumer
  ]
}
