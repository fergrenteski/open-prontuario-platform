// Open Prontuário — infraestrutura Azure (escopo: resource group).
// Uso: veja docs/DEPLOY.md. Atlas (MongoDB) é externo: informe a connection string.
targetScope = 'resourceGroup'

@description('Região dos recursos (Azure for Students pode restringir regiões).')
param location string = resourceGroup().location

@description('Região do Static Web Apps (não existe em todas as regiões).')
@allowed(['eastus2', 'centralus', 'westus2', 'westeurope', 'eastasia'])
param swaLocation string = 'eastus2'

@description('Prefixo curto dos nomes (minúsculas).')
@minLength(3)
@maxLength(12)
param prefixo string = 'openpront'

@description('Usuário do Docker Hub que publicou as imagens <usuario>/pjbl-<servico>:<tag>.')
param dockerHubUser string

param imageTag string = 'v1'

@secure()
@description('Connection string do MongoDB Atlas (M0).')
param mongodbUri string

@description('Login do administrador do Azure SQL.')
param sqlAdminLogin string = 'openprontuarioadmin'

@secure()
param sqlAdminPassword string

@secure()
@description('Segredo compartilhado X-Internal-Key.')
param internalApiKey string

@description('dev = personas com JWT HS256 (demonstração); entra = Microsoft Entra ID.')
@allowed(['dev', 'entra'])
param authMode string = 'dev'

@secure()
@description('Segredo HS256 do modo dev do BFF (ignorado em entra).')
param jwtSecret string = ''

param entraTenantId string = ''
param entraAudience string = ''

@description('E-mail do publicador do API Management.')
param apimPublisherEmail string

var sufixo = uniqueString(resourceGroup().id)

module observabilidade 'modules/observability.bicep' = {
  name: 'observabilidade'
  params: { location: location, prefixo: prefixo }
}

module servicebus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  params: { location: location, nome: 'sb-${prefixo}-${sufixo}' }
}

module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    location: location
    nome: 'sql-${prefixo}-${sufixo}'
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
  }
}

module frontend 'modules/staticwebapp.bicep' = {
  name: 'frontend'
  params: { location: swaLocation, nome: 'swa-${prefixo}-${sufixo}' }
}

module apps 'modules/containerapps.bicep' = {
  name: 'containerapps'
  params: {
    location: location
    prefixo: prefixo
    logAnalyticsName: observabilidade.outputs.logAnalyticsName
    appInsightsConnectionString: observabilidade.outputs.appInsightsConnectionString
    dockerHubUser: dockerHubUser
    imageTag: imageTag
    serviceBusNamespace: servicebus.outputs.namespaceName
    sqlServerFqdn: sql.outputs.serverFqdn
    sqlDatabase: sql.outputs.databaseName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    mongodbUri: mongodbUri
    internalApiKey: internalApiKey
    authMode: authMode
    jwtSecret: jwtSecret
    entraTenantId: entraTenantId
    entraAudience: entraAudience
    functionUrl: 'https://func-${prefixo}-${sufixo}.azurewebsites.net'
    corsOrigins: 'https://${frontend.outputs.hostname}'
  }
}

module function 'modules/functionapp.bicep' = {
  name: 'functionapp'
  params: {
    location: location
    nome: 'func-${prefixo}-${sufixo}'
    storageName: take('st${prefixo}${sufixo}', 24)
    appInsightsConnectionString: observabilidade.outputs.appInsightsConnectionString
    serviceBusNamespace: servicebus.outputs.namespaceName
    mongodbUri: mongodbUri
    msFilaUrl: apps.outputs.msFilaUrl
    internalApiKey: internalApiKey
  }
}

module gateway 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    location: location
    nome: 'apim-${prefixo}-${sufixo}'
    publisherEmail: apimPublisherEmail
    bffUrl: apps.outputs.bffUrl
    frontendOrigin: 'https://${frontend.outputs.hostname}'
  }
}

output frontendUrl string = 'https://${frontend.outputs.hostname}'
output apiGatewayUrl string = gateway.outputs.gatewayUrl
output bffSwaggerUrl string = '${apps.outputs.bffUrl}/api/docs'
output msFilaSwaggerUrl string = '${apps.outputs.msFilaUrl}/swagger-ui.html'
output msProntuarioSwaggerUrl string = '${apps.outputs.msProntuarioUrl}/swagger-ui.html'
output functionUrl string = function.outputs.url
output functionAppName string = function.outputs.nome
output staticWebAppName string = frontend.outputs.nome
output sqlServerFqdn string = sql.outputs.serverFqdn
output serviceBusNamespace string = servicebus.outputs.namespaceName
