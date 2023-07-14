param cdnProfileName string
param cdnEndpointName string
param cdnCustomDomainName string
param location string

resource dsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${cdnProfileName}-ds-identity'
  location: location
}

var roleDefinitions = [
  '426e0c7f-0c7e-4658-b36f-ff54d6c29b45' // CDN Endpoint Contributor
  'ec156ff8-a8d1-4d15-830c-5b80698ca432' // CDN Profile Contributor
]

module roleAssignments 'cdn-role.bicep' = [for roleDefinitionId in roleDefinitions: {
  name: 'cdn-role-${roleDefinitionId}'
  params: {
    cdnName: cdnProfileName
    principalId: dsIdentity.properties.principalId
    roleDefinitionId: roleDefinitionId
  }
}]

resource enableHttpsForCustomDomain 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'enableHttpsForCustomDomain'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${dsIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.42.0'
    retentionInterval: 'PT1H'
    scriptContent: 'az cdn custom-domain enable-https --resource-group ${resourceGroup().name} --name ${cdnCustomDomainName} --profile-name ${cdnProfileName} --endpoint-name ${cdnEndpointName}'
  }
}
