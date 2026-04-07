param domainName string
param subDomainName string
param cdnEndpointResourceId string
param cdnValidationToken string

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: domainName

  resource cname 'CNAME' = {
    name: subDomainName
    properties: {
      TTL: 3600
      targetResource: {
        id: cdnEndpointResourceId
      }
    }
  }

  resource cdnverify 'TXT' = {
    name: '_dnsauth.${subDomainName}'
    properties: {
      TTL: 3600
      TXTRecords: [
        {
          value: [
            cdnValidationToken
          ]
        }
      ]
    }
  }
}
