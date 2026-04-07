targetScope = 'subscription'

@description('AZD environment name (e.g., staging, production).')
param environmentName string

@description('Azure region for all resources (e.g., westeurope).')
param location string

@description('Resource group name to create/use for this environment.')
param resourceGroupName string

@description('SQL admin login name (SQL authentication).')
param sqlAdminLogin string = 'sqladmin'

@secure()
@description('SQL admin password (stored in Key Vault and referenced by apps).')
param sqlAdminPassword string

@description('Node.js runtime version (App Service Windows setting WEBSITE_NODE_DEFAULT_VERSION).')
param nodeMajorVersion string = '~20'

@description('Owner email tag (non-secret).')
param ownerEmail string = 'owner@company.com'

var resourceToken = toLower(uniqueString(subscription().id, location, environmentName))

// Per AZD+Bicep rules: az{resourcePrefix}{resourceToken}, <=32 chars, alphanumeric only.
// Some resource types have stricter limits; we take() accordingly.
var rgTags = {
  'azd-env-name': environmentName
}

var uamiName = take('azid${resourceToken}', 32)
var kvName = take('azkv${resourceToken}', 24)
var stName = take('azst${resourceToken}', 24)
var aspName = take('azasp${resourceToken}', 32)
var apiName = take('azapi${resourceToken}', 32)
var webName = take('azweb${resourceToken}', 32)
var sqlServerName = take('azsql${resourceToken}', 32)
var sqlDbName = take('azdb${resourceToken}', 32)

var blobContainerName = 'productimages'
var sqlPasswordSecretName = 'sqladminpassword'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: rgTags
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  scope: rg
  location: location
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  scope: rg
  location: location
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    sku: {
      family: 'A'
      name: 'standard'
    }
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: sqlPasswordSecretName
  parent: kv
  properties: {
    value: sqlAdminPassword
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: stName
  scope: rg
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storage
}

resource imagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: blobContainerName
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: aspName
  scope: rg
  location: location
  sku: {
    // Medium traffic baseline. Adjust after load testing.
    name: environmentName == 'production' ? 'P1v3' : 'S1'
    tier: environmentName == 'production' ? 'PremiumV3' : 'Standard'
    capacity: environmentName == 'production' ? 2 : 1
  }
  properties: {
    reserved: false
  }
}

var sqlPasswordKvRef = '@Microsoft.KeyVault(SecretUri=${sqlPasswordSecret.properties.secretUriWithVersion})'

resource apiApp 'Microsoft.Web/sites@2023-01-01' = {
  name: apiName
  scope: rg
  location: location
  tags: {
    // Rule: only App Service resources get this tag.
    'azd-service-name': 'api'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: nodeMajorVersion
        }
        {
          name: 'API_PORT'
          value: '3000'
        }
        {
          name: 'AZURE_ENV_NAME'
          value: environmentName
        }
        {
          name: 'SQL_SERVER'
          value: '${sqlServerName}.database.windows.net'
        }
        {
          name: 'SQL_DATABASE'
          value: sqlDbName
        }
        {
          name: 'SQL_USER'
          value: sqlAdminLogin
        }
        {
          name: 'SQL_PASSWORD'
          value: sqlPasswordKvRef
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storage.name
        }
        {
          name: 'BLOB_CONTAINER'
          value: imagesContainer.name
        }
        {
          name: 'KEY_VAULT_NAME'
          value: kv.name
        }
      ]
    }
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webName
  scope: rg
  location: location
  tags: {
    'azd-service-name': 'frontend'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: nodeMajorVersion
        }
        {
          name: 'AZURE_ENV_NAME'
          value: environmentName
        }
        {
          name: 'API_BASE_URL'
          // Filled after deployment (or set to apiApp default hostname).
          value: 'https://${apiApp.properties.defaultHostName}'
        }
      ]
    }
  }
}

// Mandatory App Service Site Extension resource.
// Using a known extension name from an official quickstart template.
resource apiSiteExtension 'Microsoft.Web/sites/siteextensions@2021-02-01' = {
  name: 'Microsoft.ApplicationInsights.AzureWebSites'
  parent: apiApp
}

resource webSiteExtension 'Microsoft.Web/sites/siteextensions@2021-02-01' = {
  name: 'Microsoft.ApplicationInsights.AzureWebSites'
  parent: webApp
}

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  scope: rg
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  name: sqlDbName
  parent: sqlServer
  location: location
  sku: {
    // Moderate baseline; adjust after workload profiling.
    name: environmentName == 'production' ? 'S2' : 'S0'
    tier: 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

// Allow Azure services to access the SQL server (simplest baseline).
resource sqlFirewallAzureServices 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  name: 'AllowAzureServices'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// RBAC role assignments (data plane) for the User-Assigned Managed Identity.
// Key Vault Secrets User role
resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, uami.id, 'kv-secrets-user')
  scope: kv
  properties: {
    principalId: uami.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role
resource storageBlobContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, uami.id, 'storage-blob-contrib')
  scope: storage
  properties: {
    principalId: uami.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalType: 'ServicePrincipal'
  }
}

output RESOURCE_GROUP_ID string = rg.id
output KEY_VAULT_NAME string = kv.name
output STORAGE_ACCOUNT_NAME string = storage.name
output API_APP_NAME string = apiApp.name
output FRONTEND_APP_NAME string = webApp.name
output SQL_SERVER_FQDN string = '${sqlServerName}.database.windows.net'
output SQL_DATABASE_NAME string = sqlDb.name
