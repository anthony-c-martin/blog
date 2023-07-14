@description('The base domain name (e.g. "foo.com")')
param domainName string

@description('The child domain name (e.g. "bar")')
param subDomainName string

@description('The name of the resource group where the dnsZone resource exists')
param dnsResourceGroup string

@description('The location to deploy non-global resources')
param location string = resourceGroup().location

var fullSubDomainName = '${subDomainName}.${domainName}'

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

resource cdnProfile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: subDomainName
  location: 'global'
  sku: {
    name: 'Standard_Microsoft'
  }
}

resource cdnEnpoint 'Microsoft.Cdn/profiles/endpoints@2021-06-01' = {
  parent: cdnProfile
  name: replace(fullSubDomainName, '.', '-')
  location: 'global'
  properties: {
    originHostHeader: storageHostname
    // we enforce an http redirect with the rules engine, but this must be set to true for it to work
    isHttpAllowed: true
    isHttpsAllowed: true
    isCompressionEnabled: true
    queryStringCachingBehavior: 'IgnoreQueryString'
    optimizationType: 'GeneralWebDelivery'
    contentTypesToCompress: [
      'application/eot'
      'application/font'
      'application/font-sfnt'
      'application/javascript'
      'application/json'
      'application/opentype'
      'application/otf'
      'application/pkcs7-mime'
      'application/truetype'
      'application/ttf'
      'application/vnd.ms-fontobject'
      'application/xhtml+xml'
      'application/xml'
      'application/xml+rss'
      'application/x-font-opentype'
      'application/x-font-truetype'
      'application/x-font-ttf'
      'application/x-httpd-cgi'
      'application/x-javascript'
      'application/x-mpegurl'
      'application/x-opentype'
      'application/x-otf'
      'application/x-perl'
      'application/x-ttf'
      'font/eot'
      'font/ttf'
      'font/otf'
      'font/opentype'
      'image/svg+xml'
      'text/css'
      'text/csv'
      'text/html'
      'text/javascript'
      'text/js'
      'text/plain'
      'text/richtext'
      'text/tab-separated-values'
      'text/xml'
      'text/x-script'
      'text/x-component'
      'text/x-java-source'
    ]
    origins: [
      {
        name: replace(storageHostname, '.', '-')
        properties: {
          hostName: storageHostname
          originHostHeader: storageHostname
        }
      }
    ]
    deliveryPolicy: {
      rules: [
        {
          name: 'EnforceHTTPS'
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
        }
      ]
    }
  }
}

module dns 'dns.bicep' = {
  name: 'dns'
  scope: resourceGroup(dnsResourceGroup)
  params: {
    cdnEndpointFqdn: cdnEnpoint.properties.hostName
    cdnEndpointId: cdnEnpoint.id
    domainName: domainName
    subDomainName: subDomainName
  }
}

resource cdnDomain 'Microsoft.Cdn/profiles/endpoints/customDomains@2021-06-01' = {
  parent: cdnEnpoint
  name: replace(fullSubDomainName, '.', '-')
  properties: {
    hostName: fullSubDomainName
  }
  dependsOn: [
    dns
  ]
}

module enableHttps 'cdn-https.bicep' = {
  name: 'cdn-https'
  params: {
    cdnCustomDomainName: cdnDomain.name
    cdnEndpointName: cdnEnpoint.name
    cdnProfileName: cdnProfile.name
    location: location
  }
}

output stgAccName string = storage.name
