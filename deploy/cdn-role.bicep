param cdnName string
param roleDefinitionId string
param principalId string

resource cdnProfile 'Microsoft.Cdn/profiles@2021-06-01' existing = {
  name: cdnName
}

resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: roleDefinitionId
}

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(cdnProfile.id, roleDefinitionId, principalId)
  scope: cdnProfile
  properties: {
    principalType: 'ServicePrincipal'
    principalId: principalId
    roleDefinitionId: roleDefinition.id
  }
}
