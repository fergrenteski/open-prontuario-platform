// Azure Functions (Linux, plano Flex Consumption FC1, Java 17).
// O Y1 (Linux Consumption) está sendo aposentado e tem cota zero no Azure for Students.
param location string
param nome string
param storageName string
param appInsightsConnectionString string
param serviceBusNamespace string
@secure()
param mongodbUri string
param msFilaUrl string
@secure()
param internalApiKey string

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespace
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// Container onde o Flex Consumption guarda o pacote publicado.
resource pacotes 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storage.name}/default/deploy'
}

resource plano 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${nome}'
  location: location
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  kind: 'functionapp'
  properties: { reserved: true }
}

var storageConnection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: nome
  location: location
  kind: 'functionapp,linux'
  dependsOn: [pacotes]
  properties: {
    serverFarmId: plano.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}deploy'
          authentication: { type: 'StorageAccountConnectionString', storageAccountConnectionStringName: 'AzureWebJobsStorage' }
        }
      }
      scaleAndConcurrency: { maximumInstanceCount: 40, instanceMemoryMB: 2048 }
      runtime: { name: 'java', version: '17' }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConnection }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'ServiceBusConnection', value: listKeys('${sb.id}/AuthorizationRules/RootManageSharedAccessKey', '2022-10-01-preview').primaryConnectionString }
        { name: 'SERVICEBUS_TOPIC', value: 'eventos-atendimento' }
        { name: 'SERVICEBUS_SUBSCRIPTION', value: 'agregador' }
        { name: 'MONGODB_URI', value: mongodbUri }
        { name: 'MONGODB_DATABASE', value: 'visao' }
        { name: 'MS_FILA_URL', value: msFilaUrl }
        { name: 'INTERNAL_API_KEY', value: internalApiKey }
      ]
    }
  }
}

output url string = 'https://${app.properties.defaultHostName}'
output nome string = app.name
