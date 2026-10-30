param location string
param nome string
param adminLogin string
@secure()
param adminPassword string

resource server 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: nome
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Permite conexões vindas de serviços Azure (Container Apps).
resource firewallAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: server
  name: 'AllowAzureServices'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

// Oferta gratuita do Azure SQL Database (serverless, pausa ao esgotar a cota mensal).
resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: server
  name: 'openprontuario'
  location: location
  sku: { name: 'GP_S_Gen5_2', tier: 'GeneralPurpose', family: 'Gen5', capacity: 2 }
  properties: {
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'AutoPause'
    autoPauseDelay: 60
    minCapacity: json('0.5')
  }
}

output serverFqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
