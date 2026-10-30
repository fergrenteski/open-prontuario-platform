param location string
param nome string

// Standard é o tier mais barato com tópicos e subscriptions.
resource namespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: nome
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
}

resource topico 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: namespace
  name: 'eventos-atendimento'
  properties: {
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    defaultMessageTimeToLive: 'P1D'
  }
}

resource agregador 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: topico
  name: 'agregador'
  properties: {
    maxDeliveryCount: 5
    lockDuration: 'PT1M'
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P1D'
  }
}

output namespaceName string = namespace.name
