// =============================================================================
// Secure Azure Hub-and-Spoke Network Architecture
// -----------------------------------------------------------------------------
// Deploys the security and monitoring layer (Bastion, NSGs, ASGs, Load Balancer,
// Private Endpoint, Log Analytics workspace, CPU alert) on top of a pre-existing
// network and compute foundation in resource group rg-enterprise-prod-001
// (UK South).
//
// PREREQUISITE RESOURCES (must exist before deployment):
//   - vnet-hub with subnets: AzureBastionSubnet, snet-hub-mgmt
//   - vnet-spoke with subnets: snet-spoke-ingress, snet-spoke-web, snet-spoke-data
//   - Bidirectional VNet peering between vnet-hub and vnet-spoke
//   - VM-WEB-01 and VM-WEB-02 (Ubuntu, Nginx)
//   - Storage account stsamentprod001 (public network access disabled)
//   - Private DNS zone privatelink.blob.core.windows.net (linked to vnet-spoke)
//   - Public IP pip-lb-web (Standard SKU, for the Load Balancer frontend)
//
// PROJECT STATUS: Infrastructure was deployed end-to-end, validated, and then
// torn down to control lab costs. Subscription ID and alert email parameterised
// and redacted in this template.
//
// Author: Samra Saher  |  Cert: Microsoft AZ-104
// =============================================================================

@description('Target Azure subscription ID. Replace before deployment.')
param subscriptionId string = '00000000-0000-0000-0000-000000000000'

@description('Resource group hosting the foundation resources.')
param resourceGroupName string = 'rg-enterprise-prod-001'

@description('Email address to receive CPU alert notifications.')
param alertEmail string = 'YOUR-EMAIL@example.com'

@description('Azure region for all resources.')
param location string = 'uksouth'

// -----------------------------------------------------------------------------
// External resource IDs (foundation layer)
// -----------------------------------------------------------------------------
var vmWeb01Id     = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Compute/virtualMachines/VM-WEB-01'
var vmWeb02Id     = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Compute/virtualMachines/VM-WEB-02'
var vnetHubId     = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/virtualNetworks/vnet-hub'
var vnetSpokeId   = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/virtualNetworks/vnet-spoke'
var pipLbWebId    = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/publicIPAddresses/pip-lb-web'
var storageId     = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Storage/storageAccounts/stsamentprod001'
var blobDnsZoneId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'

// =============================================================================
// Application Security Group — bound to web tier VM NICs
// =============================================================================
resource asgWebServers 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-web-servers'
  location: location
}

// =============================================================================
// Network Security Groups — one per spoke subnet, rules defined inline
// =============================================================================
resource nsgSpokeWeb 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-spoke-web'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-http-inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource nsgSpokeData 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-spoke-data'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-from-web-asg'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceApplicationSecurityGroups: [
            {
              id: asgWebServers.id
            }
          ]
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

// =============================================================================
// Availability Sets — fault-domain isolation for web tier VMs
// =============================================================================
resource avsetWeb 'Microsoft.Compute/availabilitySets@2024-07-01' = {
  name: 'avset-web'
  location: location
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformUpdateDomainCount: 5
    platformFaultDomainCount: 2
    virtualMachines: [
      {
        id: vmWeb01Id
      }
    ]
  }
}

resource avsetWeb02 'Microsoft.Compute/availabilitySets@2024-07-01' = {
  name: 'avset-web-02'
  location: location
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformUpdateDomainCount: 5
    platformFaultDomainCount: 2
    virtualMachines: [
      {
        id: vmWeb02Id
      }
    ]
  }
}

// =============================================================================
// Standard Load Balancer — distributes HTTP traffic across web VMs
// =============================================================================
resource lbWebPublic 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: 'lb-web-public'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend-web'
        properties: {
          publicIPAddress: {
            id: pipLbWebId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backend-web'
      }
    ]
    probes: [
      {
        name: 'probe-http'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 1
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-web-public', 'frontend-web')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-web-public', 'backend-web')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-web-public', 'probe-http')
          }
          frontendPort: 80
          backendPort: 80
          protocol: 'Tcp'
          idleTimeoutInMinutes: 4
          disableOutboundSnat: true
        }
      }
    ]
    outboundRules: [
      {
        name: 'outbound-internet'
        properties: {
          frontendIPConfigurations: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-web-public', 'frontend-web')
            }
          ]
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-web-public', 'backend-web')
          }
          protocol: 'All'
          allocatedOutboundPorts: 1024
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// =============================================================================
// Azure Bastion — secure RDP/SSH without exposing VM public IPs
// =============================================================================
resource pipBastionHub 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-bastion-hub'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource bastionHub 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'bastion-hub'
  location: location
  sku: {
    name: 'Basic'
  }
  zones: ['1']
  properties: {
    scaleUnits: 2
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          publicIPAddress: {
            id: pipBastionHub.id
          }
          subnet: {
            id: '${vnetHubId}/subnets/AzureBastionSubnet'
          }
        }
      }
    ]
  }
}

// =============================================================================
// Private Endpoint — Blob Storage over Microsoft backbone (no public internet)
// =============================================================================
resource peStorageData 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-storage-data'
  location: location
  properties: {
    subnet: {
      id: '${vnetSpokeId}/subnets/snet-spoke-data'
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-storage-data'
        properties: {
          privateLinkServiceId: storageId
          groupIds: ['blob']
        }
      }
    ]
    customNetworkInterfaceName: 'pe-storage-data-nic'
  }
}

resource peStorageDataDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peStorageData
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: blobDnsZoneId
        }
      }
    ]
  }
}

// =============================================================================
// Log Analytics workspace + CPU alert pipeline
// =============================================================================
resource lawEnterpriseProd 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-enterprise-prod'
  location: location
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource agCpuAlert 'Microsoft.Insights/actionGroups@2024-10-01-preview' = {
  name: 'ag-cpu-alert'
  location: 'global'
  properties: {
    groupShortName: 'ag-cpu'
    enabled: true
    emailReceivers: [
      {
        name: 'email-alert'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource alertHighCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-cpu'
  location: 'global'
  properties: {
    description: 'Triggers when VM CPU exceeds 80% over a 5-minute window.'
    severity: 2
    enabled: true
    scopes: [
      vmWeb01Id
      vmWeb02Id
    ]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'cpu-over-80'
          metricNamespace: 'microsoft.compute/virtualmachines'
          metricName: 'Percentage CPU'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: agCpuAlert.id
      }
    ]
  }
}
