param location string
param prefix string
param groupId string
param domainName string

/* build isolated vnet to house components */
resource isolatednetwork 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'vnet-${prefix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        id: 'subnet-${prefix}-appgw'
        name: 'subnet-${prefix}-appgw'
        properties: {
          addressPrefix: '10.10.1.0/27'
        }
      }
      {
        id: 'subnet-${prefix}-apim'
        name: 'subnet-${prefix}-apim'
        properties: {
          addressPrefix: '10.10.2.0/27'
        }
      }
    ]
  }
}

/* public IP will be used on the Application Gateway */
resource appgwpublicip 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: 'pip-${prefix}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

/* private DNS zone is needed on the vnet to map FQDN to private IP on the APIM */
resource privatedns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: domainName
  location: 'global'
}

/* this will link the private DNS zone with the isolated vnet */
resource privateDNSLinktoVNET 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privatedns.name}/privateDNSLinktoVNET'
  location: 'global'
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: isolatednetwork.id
    }
  }
}

/* This managed identity will be used to pull certificates from keyvault */
resource apimUserIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'mi-apim-${prefix}'
  location: location
}

/* This keyvault will be used to house certificates */
resource keyvault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: 'kv-${prefix}'
  location: location
  dependsOn: [
    apimUserIdentity
  ]
  properties: {
    tenantId: tenant().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [
      {
        objectId: apimUserIdentity.properties.principalId
        tenantId: tenant().tenantId
        permissions:{
          certificates: [
            'all'
          ]
          keys: [
            'all'
          ]
          secrets: [
            'all'
          ]
          storage: [
            'all'
          ]
        }
      }
      {
        objectId: groupId
        tenantId: tenant().tenantId
        permissions:{
          certificates: [
            'all'
          ]
          keys: [
            'all'
          ]
          secrets: [
            'all'
          ]
          storage: [
            'all'
          ]
        }
      }
    ]
  }
}

/* Per Microsoft, is not not possible at this time to import a certificate to KeyVault using ARM/Bicep */
/* The recommended path is to use Azure API, the Azure CLI, or PowerShell */
