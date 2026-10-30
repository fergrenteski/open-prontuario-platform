// Container Apps (Consumption) para BFF, MS Fila e MS Prontuário, com imagens do Docker Hub.
param location string
param prefixo string
param logAnalyticsName string
param appInsightsConnectionString string
param dockerHubUser string
param imageTag string
param serviceBusNamespace string
param sqlServerFqdn string
param sqlDatabase string
param sqlAdminLogin string
@secure()
param sqlAdminPassword string
@secure()
param mongodbUri string
@secure()
param internalApiKey string
param authMode string
@secure()
param jwtSecret string
param entraTenantId string
param entraAudience string
param functionUrl string
param corsOrigins string

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespace
}

var serviceBusConnection = listKeys('${sb.id}/AuthorizationRules/RootManageSharedAccessKey', '2022-10-01-preview').primaryConnectionString

resource ambiente 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${prefixo}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

// Escala a zero fora de uso para economizar crédito (cold start aceito, ver arc42 §11).
var escala = {
  minReplicas: 0
  maxReplicas: 3
  rules: [{ name: 'http', http: { metadata: { concurrentRequests: '50' } } }]
}

resource msFila 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-ms-fila-sql'
  location: location
  properties: {
    managedEnvironmentId: ambiente.id
    configuration: {
      ingress: { external: true, targetPort: 8081, transport: 'auto' }
      secrets: [
        { name: 'db-password', value: sqlAdminPassword }
        { name: 'servicebus', value: serviceBusConnection }
        { name: 'internal-key', value: internalApiKey }
      ]
    }
    template: {
      containers: [
        {
          name: 'ms-fila-sql'
          image: 'docker.io/${dockerHubUser}/pjbl-ms-fila-sql:${imageTag}'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'PORT', value: '8081' }
            { name: 'DB_URL', value: 'jdbc:sqlserver://${sqlServerFqdn}:1433;databaseName=${sqlDatabase};encrypt=true;trustServerCertificate=false;loginTimeout=60' }
            { name: 'DB_USER', value: sqlAdminLogin }
            { name: 'DB_PASSWORD', secretRef: 'db-password' }
            { name: 'SERVICEBUS_CONNECTION_STRING', secretRef: 'servicebus' }
            { name: 'SERVICEBUS_TOPIC', value: 'eventos-atendimento' }
            { name: 'INTERNAL_API_KEY', secretRef: 'internal-key' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: escala
    }
  }
}

resource msProntuario 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-ms-prontuario-mongo'
  location: location
  properties: {
    managedEnvironmentId: ambiente.id
    configuration: {
      ingress: { external: true, targetPort: 8082, transport: 'auto' }
      secrets: [
        { name: 'mongodb-uri', value: mongodbUri }
        { name: 'internal-key', value: internalApiKey }
      ]
    }
    template: {
      containers: [
        {
          name: 'ms-prontuario-mongo'
          image: 'docker.io/${dockerHubUser}/pjbl-ms-prontuario-mongo:${imageTag}'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'PORT', value: '8082' }
            { name: 'MONGODB_URI', secretRef: 'mongodb-uri' }
            { name: 'MONGODB_DATABASE', value: 'prontuario' }
            { name: 'MS_FILA_URL', value: 'https://${msFila.properties.configuration.ingress.fqdn}' }
            { name: 'INTERNAL_API_KEY', secretRef: 'internal-key' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: escala
    }
  }
}

resource bff 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-bff'
  location: location
  properties: {
    managedEnvironmentId: ambiente.id
    configuration: {
      ingress: { external: true, targetPort: 3000, transport: 'auto' }
      secrets: [
        { name: 'internal-key', value: internalApiKey }
        { name: 'jwt-secret', value: empty(jwtSecret) ? 'nao-usado-em-modo-entra' : jwtSecret }
      ]
    }
    template: {
      containers: [
        {
          name: 'bff'
          image: 'docker.io/${dockerHubUser}/pjbl-bff:${imageTag}'
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: [
            { name: 'PORT', value: '3000' }
            { name: 'NODE_ENV', value: 'production' }
            { name: 'AUTH_MODE', value: authMode }
            // Demonstração acadêmica: modo dev em produção só com opt-in explícito.
            { name: 'ALLOW_DEV_AUTH_IN_PRODUCTION', value: authMode == 'dev' ? 'true' : 'false' }
            { name: 'JWT_SECRET', secretRef: 'jwt-secret' }
            { name: 'ENTRA_TENANT_ID', value: entraTenantId }
            { name: 'ENTRA_AUDIENCE', value: entraAudience }
            { name: 'MS_FILA_URL', value: 'https://${msFila.properties.configuration.ingress.fqdn}' }
            { name: 'MS_PRONTUARIO_URL', value: 'https://${msProntuario.properties.configuration.ingress.fqdn}' }
            { name: 'FN_VISAO_URL', value: functionUrl }
            { name: 'INTERNAL_API_KEY', secretRef: 'internal-key' }
            { name: 'CORS_ORIGINS', value: corsOrigins }
            { name: 'UPSTREAM_TIMEOUT_MS', value: '10000' }
          ]
        }
      ]
      scale: escala
    }
  }
}

output msFilaUrl string = 'https://${msFila.properties.configuration.ingress.fqdn}'
output msProntuarioUrl string = 'https://${msProntuario.properties.configuration.ingress.fqdn}'
output bffUrl string = 'https://${bff.properties.configuration.ingress.fqdn}'
