// Azure Functions (Linux, plano Consumption Y1, Java 17).
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

resource plano 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${nome}'
  location: location
  sku: { name: 'Y1', tier: 'Dynamic' }
  kind: 'functionapp'
  properties: { reserved: true }
}

var storageConnection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: nome
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: plano.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Java|17'
      minTlsVersion: '1.2'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConnection }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'java' }
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
