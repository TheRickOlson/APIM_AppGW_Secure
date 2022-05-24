param location string
param prefix string
param domainName string
param gatewayEndpoint string
param managementEndpoint string
param devPortalEndpoint string
param scmEndpoint string

param appGatewayName string = 'appgw-${prefix}'
param feIPConfigName string = 'appgwFrontEndIP'

/* pull existing resources to use throughout the configuration steps */
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-08-01' existing = {
  name: 'vnet-${prefix}'
}

resource keyvault 'Microsoft.KeyVault/vaults@2021-10-01' existing = {
  name: 'kv-${prefix}'
}

resource kvGatewayCert 'Microsoft.KeyVault/vaults/secrets@2021-10-01' existing = {
  name: '${keyvault.name}/APIM-${gatewayEndpoint}'
}

resource kvManagementCert 'Microsoft.KeyVault/vaults/secrets@2021-10-01' existing = {
  name: '${keyvault.name}/APIM-${managementEndpoint}'
}

resource kvDevPortalCert 'Microsoft.KeyVault/vaults/secrets@2021-10-01' existing = {
  name: '${keyvault.name}/APIM-${devPortalEndpoint}'
}

resource kvSCMCert 'Microsoft.KeyVault/vaults/secrets@2021-10-01' existing = {
  name: '${keyvault.name}/APIM-${scmEndpoint}'
}

resource rootCA 'Microsoft.KeyVault/vaults/secrets@2021-10-01' existing = {
  name: '${keyvault.name}/rootCA'
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2021-08-01' existing = {
  name: 'pip-${prefix}'
}

resource userAssignedID 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: 'mi-apim-${prefix}'
}

resource privateDNS 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: domainName
}

/* configure the APIM to expose endpoints */
resource apim 'Microsoft.ApiManagement/service@2021-12-01-preview' = {
  name: 'apim-${prefix}-poc'
  location: location
  sku: {
    capacity: 1
    name: 'Developer'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedID.id}': {}
    }
  }
  properties:{
    publisherEmail: 'youremail@domain.com'
    publisherName: 'your name'
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: '${virtualNetwork.id}/subnets/subnet-${prefix}-apim'
    }
    hostnameConfigurations: [
      {
        hostName: '${gatewayEndpoint}.${domainName}'
        type: 'Proxy'
        certificateSource: 'KeyVault'
        keyVaultId: '${keyvault.properties.vaultUri}secrets/APIM-${gatewayEndpoint}'
        identityClientId: userAssignedID.properties.clientId
      }
      {
        hostName: '${managementEndpoint}.${domainName}'
        type: 'Management'
        certificateSource: 'KeyVault'
        keyVaultId: '${keyvault.properties.vaultUri}secrets/APIM-${managementEndpoint}'
        identityClientId: userAssignedID.properties.clientId
      }
      {
        hostName: '${devPortalEndpoint}.${domainName}'
        type: 'DeveloperPortal'
        certificateSource: 'KeyVault'
        keyVaultId: '${keyvault.properties.vaultUri}secrets/APIM-${devPortalEndpoint}'
        identityClientId: userAssignedID.properties.clientId
      }
      {
        hostName: '${scmEndpoint}.${domainName}'
        type: 'Scm'
        certificateSource: 'KeyVault'
        keyVaultId: '${keyvault.properties.vaultUri}secrets/APIM-${scmEndpoint}'
        identityClientId: userAssignedID.properties.clientId
      }
    ]
  }
}

/* Deploy Application Gateway */
/* used the below link as reference */
/* https://github.com/Azure/bicep/blob/main/docs/examples/101/application-gateway-v2-autoscale-create/main.bicep */
resource applicationGateway 'Microsoft.Network/applicationGateways@2021-08-01' = {
  name: appGatewayName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedID.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-gateway-config'
        properties: {
          subnet: {
            id: '${virtualNetwork.id}/subnets/subnet-${prefix}-appgw'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: feIPConfigName
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'defaultFrontEndPort'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        id: 'be-${gatewayEndpoint}'
        name: 'be-${gatewayEndpoint}'
        properties: {
          backendAddresses: [
            {
              fqdn: '${gatewayEndpoint}.${domainName}'
            }
          ]
        }
      }
      {
        id: 'be-${managementEndpoint}'
        name: 'be-${managementEndpoint}'
        properties: {
          backendAddresses: [
            {
              fqdn: '${managementEndpoint}.${domainName}'
            }
          ]
        }
      }
      {
        id: 'be-${devPortalEndpoint}'
        name: 'be-${devPortalEndpoint}'
        properties: {
          backendAddresses: [
            {
              fqdn: '${devPortalEndpoint}.${domainName}'
            }
          ]
        }
      }
      {
        id: 'be-${scmEndpoint}'
        name: 'be-${scmEndpoint}'
        properties: {
          backendAddresses: [
            {
              fqdn: '${scmEndpoint}.${domainName}'
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'beSettings-${gatewayEndpoint}'
        properties: {
          port: 443
          protocol:'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probe: {
            id: resourceId('Microsoft.Network/applicationgateways/probes',appGatewayName,'probe-${gatewayEndpoint}')
          }
          trustedRootCertificates: [
            {
              id: resourceId('Microsoft.Network/applicationgateways/trustedRootCertificates', appGatewayName, 'rootCA')
            }
          ]
        }
      }
      {
        name: 'beSettings-${managementEndpoint}'
        properties: {
          port: 443
          protocol:'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          hostName: '${managementEndpoint}.${domainName}'
          probe: {
            id: resourceId('Microsoft.Network/applicationgateways/probes',appGatewayName,'probe-${managementEndpoint}')
          }
          trustedRootCertificates: [
            {
              id: resourceId('Microsoft.Network/applicationgateways/trustedRootCertificates', appGatewayName, 'rootCA')
            }
          ]
        }
      }
      {
        name: 'beSettings-${devPortalEndpoint}'
        properties: {
          port: 443
          protocol:'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          hostName: '${devPortalEndpoint}.${domainName}'
          probe: {
            id: resourceId('Microsoft.Network/applicationgateways/probes',appGatewayName,'probe-${devPortalEndpoint}')
          }
          trustedRootCertificates: [
            {
              id: resourceId('Microsoft.Network/applicationgateways/trustedRootCertificates', appGatewayName, 'rootCA')
            }
          ]
        }
      }
      {
        name: 'beSettings-${scmEndpoint}'
        properties: {
          port: 443
          protocol:'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          hostName: '${scmEndpoint}.${domainName}'
        }
      }
    ]
    httpListeners: [
      {
        name: 'Listener-${gatewayEndpoint}'
        properties: {
          hostName:'${gatewayEndpoint}.${domainName}'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationgateways/frontendIPConfigurations',appGatewayName,feIPConfigName)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontEndPorts', appGatewayName, 'defaultFrontEndPort')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates',appGatewayName,'cert-${gatewayEndpoint}') /* no clue if this will work*/
          }
        }
      }
      {
        name: 'Listener-${managementEndpoint}'
        properties: {
          hostName:'${managementEndpoint}.${domainName}'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationgateways/frontendIPConfigurations',appGatewayName,feIPConfigName)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontEndPorts', appGatewayName, 'defaultFrontEndPort')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates',appGatewayName,'cert-${managementEndpoint}') /* no clue if this will work*/
          }
        }
      }
      {
        name: 'Listener-${devPortalEndpoint}'
        properties: {
          hostName:'${devPortalEndpoint}.${domainName}'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationgateways/frontendIPConfigurations',appGatewayName,feIPConfigName)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontEndPorts', appGatewayName, 'defaultFrontEndPort')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates',appGatewayName,'cert-${devPortalEndpoint}') /* no clue if this will work*/
          }
        }
      }
      {
        name: 'Listener-${scmEndpoint}'
        properties: {
          hostName:'${scmEndpoint}.${domainName}'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationgateways/frontendIPConfigurations',appGatewayName,feIPConfigName)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontEndPorts', appGatewayName, 'defaultFrontEndPort')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates',appGatewayName,'cert-${scmEndpoint}') /* no clue if this will work*/
          }
        }
      }
    ]
    probes: [
      {
        id: 'probe-${gatewayEndpoint}'
        name: 'probe-${gatewayEndpoint}'
        properties: {
          host: '${gatewayEndpoint}.${domainName}'
          interval: 30
          path: '/status-0123456789abcdef'
          pickHostNameFromBackendHttpSettings: false
          protocol: 'Https'
          timeout: 120
          unhealthyThreshold: 0
        }
      }
      {
        id: 'probe-${managementEndpoint}'
        name: 'probe-${managementEndpoint}'
        properties: {
          host: '${managementEndpoint}.${domainName}'
          interval: 30
          path: '/ServiceStatus'
          pickHostNameFromBackendHttpSettings: false
          protocol: 'Https'
          timeout: 120
          unhealthyThreshold: 0
        }
      }
      {
        id: 'probe-${devPortalEndpoint}'
        name: 'probe-${devPortalEndpoint}'
        properties: {
          host: '${devPortalEndpoint}.${domainName}'
          interval: 30
          path: '/signin'
          pickHostNameFromBackendHttpSettings: false
          protocol: 'Https'
          timeout: 120
          unhealthyThreshold: 0
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'routingRule-${gatewayEndpoint}'
        properties: {
          ruleType: 'Basic'
          priority: 10
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners',appGatewayName,'Listener-${gatewayEndpoint}')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools',appGatewayName,'be-${gatewayEndpoint}')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.network/applicationGateways/backendHttpSettingsCollection',appGatewayName,'beSettings-${gatewayEndpoint}')
          }
        }
      }
      {
        name: 'routingRule-${managementEndpoint}'
        properties: {
          ruleType: 'Basic'
          priority: 20
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners',appGatewayName,'Listener-${managementEndpoint}')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools',appGatewayName,'be-${managementEndpoint}')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.network/applicationGateways/backendHttpSettingsCollection',appGatewayName,'beSettings-${managementEndpoint}')
          }
        }
      }
      {
        name: 'routingRule-${devPortalEndpoint}'
        properties: {
          ruleType: 'Basic'
          priority: 30
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners',appGatewayName,'Listener-${devPortalEndpoint}')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools',appGatewayName,'be-${devPortalEndpoint}')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.network/applicationGateways/backendHttpSettingsCollection',appGatewayName,'beSettings-${devPortalEndpoint}')
          }
        }
      }
      {
        name: 'routingRule-${scmEndpoint}'
        properties: {
          ruleType: 'Basic'
          priority: 40
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners',appGatewayName,'Listener-${scmEndpoint}')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools',appGatewayName,'be-${scmEndpoint}')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.network/applicationGateways/backendHttpSettingsCollection',appGatewayName,'beSettings-${scmEndpoint}')
          }
        }
      }
    ]
    sslCertificates: [
      {
        id: 'cert-${gatewayEndpoint}'
        name: 'cert-${gatewayEndpoint}'
        properties: {
          keyVaultSecretId: kvGatewayCert.properties.secretUri
        }
      }
      {
        id: 'cert-${managementEndpoint}'
        name: 'cert-${managementEndpoint}'
        properties: {
          keyVaultSecretId: kvManagementCert.properties.secretUri
        }
      }
      {
        id: 'cert-${devPortalEndpoint}'
        name: 'cert-${devPortalEndpoint}'
        properties: {
          keyVaultSecretId: kvDevPortalCert.properties.secretUri
        }
      }
      {
        id: 'cert-${scmEndpoint}'
        name: 'cert-${scmEndpoint}'
        properties: {
          keyVaultSecretId: kvSCMCert.properties.secretUri
        }
      }
    ]

    trustedRootCertificates: [
      {
        id: 'rootCA'
        name: 'rootCA'
        properties: {
          data: loadFileAsBase64('./resources/rootcert.cer')
        }
      }
    ]
  }
}

/* add DNS records to private DNS zone */
/* DNS records are for mapping the APIM endpoints to the private IP of the APIM */
/* the only resource that uses these are the backend pools of the app gateway */
resource apiDNSrecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: gatewayEndpoint
  parent: privateDNS
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  }
}

resource managementDNSrecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: managementEndpoint
  parent: privateDNS
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  }
}

resource devPortalDNSrecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: devPortalEndpoint
  parent: privateDNS
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  }
}

resource scmDNSrecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: scmEndpoint
  parent: privateDNS
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  }
}
