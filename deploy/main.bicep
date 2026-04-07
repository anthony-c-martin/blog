@description('The base domain name (e.g. "foo.com")')
param domainName string

@description('The child domain name (e.g. "bar")')
param subDomainName string

@description('The name of the resource group where the dnsZone resource exists')
param dnsResourceGroup string

@description('The location to deploy non-global resources')
param location string = resourceGroup().location

var fullSubDomainName = '${subDomainName}.${domainName}'
var domainResourceName = replace(fullSubDomainName, '.', '-')

resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: '${subDomainName}${uniqueString(resourceGroup().id)}'
    location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: true
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

var storageHostname = replace(replace(storage.properties.primaryEndpoints.web, 'https://', ''), '/', '')

resource cdnProfile 'Microsoft.Cdn/profiles@2024-06-01-preview' = {
  name: subDomainName
  location: 'Global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 30
  }
}

resource afdEndpoint 'Microsoft.Cdn/profiles/afdendpoints@2024-06-01-preview' = {
  parent: cdnProfile
  name: domainResourceName
  location: 'Global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource ruleSet 'Microsoft.Cdn/profiles/rulesets@2024-06-01-preview' = {
  parent: cdnProfile
  name: 'default'
}

resource customDomain 'Microsoft.Cdn/profiles/customdomains@2024-06-01-preview' = {
  parent: cdnProfile
  name: domainResourceName
  properties: {
    hostName: fullSubDomainName
    tlsSettings: {
      certificateType: 'ManagedCertificate'
      minimumTlsVersion: 'TLS12'
      cipherSuiteSetType: 'TLS12_2022'
    }
  }
}

module dns 'dns.bicep' = {
  name: 'dns'
  scope: resourceGroup(dnsResourceGroup)
  params: {
    domainName: domainName
    subDomainName: subDomainName
    cdnEndpointResourceId: afdEndpoint.id
    cdnValidationToken: customDomain.properties.validationProperties.validationToken
  }
}

resource originGroup 'Microsoft.Cdn/profiles/origingroups@2024-06-01-preview' = {
  parent: cdnProfile
  name: domainResourceName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 2
      additionalLatencyInMilliseconds: 0
    }
  }
}

resource storageOrigin 'Microsoft.Cdn/profiles/origingroups/origins@2024-06-01-preview' = {
  parent: originGroup
  name: domainResourceName
  properties: {
    hostName: storageHostname
    originHostHeader: storageHostname
  }
}

resource enforceHttpsRule 'Microsoft.Cdn/profiles/rulesets/rules@2024-06-01-preview' = {
  parent: ruleSet
  name: 'EnforceHTTPS'
  properties: {
    order: 1
    conditions: [
      {
        name: 'RequestScheme'
        parameters: {
          typeName: 'DeliveryRuleRequestSchemeConditionParameters'
          matchValues: [
            'HTTP'
          ]
          operator: 'Equal'
          negateCondition: false
          transforms: []
        }
      }
    ]
    actions: [
      {
        name: 'UrlRedirect'
        parameters: {
          typeName: 'DeliveryRuleUrlRedirectActionParameters'
          redirectType: 'Found'
          destinationProtocol: 'Https'
        }
      }
    ]
    matchProcessingBehavior: 'Continue'
  }
}

resource afdRoute 'Microsoft.Cdn/profiles/afdendpoints/routes@2024-06-01-preview' = {
  parent: afdEndpoint
  name: domainResourceName
  properties: {
    customDomains: [
      {
        id: customDomain.id
      }
    ]
    originGroup: {
      id: originGroup.id
    }
    ruleSets: [
      {
        id: ruleSet.id
      }
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'MatchRequest'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Disabled'
    enabledState: 'Enabled'
  }
}

output stgAccName string = storage.name
