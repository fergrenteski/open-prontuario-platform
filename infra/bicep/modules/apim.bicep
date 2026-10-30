// API Gateway: Azure API Management (Consumption). Entrada única /api/* → BFF.
param location string
param nome string
param publisherEmail string
param bffUrl string
param frontendOrigin string

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: nome
  location: location
  sku: { name: 'Consumption', capacity: 0 }
  properties: {
    publisherEmail: publisherEmail
    publisherName: 'Open Prontuário (PJBL)'
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'open-prontuario'
  properties: {
    displayName: 'Open Prontuário'
    path: 'api'
    protocols: ['https']
    serviceUrl: '${bffUrl}/api'
    // A chave identifica o cliente para o rate limit; a autenticação do usuário é o JWT validado no BFF.
    subscriptionRequired: true
    subscriptionKeyParameterNames: { header: 'Ocp-Apim-Subscription-Key', query: 'subscription-key' }
  }
}

var metodos = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']

resource operacoes 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = [for m in metodos: {
  parent: api
  name: 'todas-${toLower(m)}'
  properties: {
    displayName: '${m} /*'
    method: m
    urlTemplate: '/*'
  }
}]

resource politica 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    // Strings multilinha do Bicep não interpolam; o placeholder é trocado aqui.
    value: replace('''
<policies>
  <inbound>
    <cors allow-credentials="false">
      <allowed-origins><origin>__ORIGEM_FRONTEND__</origin></allowed-origins>
      <allowed-methods preflight-result-max-age="300"><method>*</method></allowed-methods>
      <allowed-headers><header>*</header></allowed-headers>
      <expose-headers><header>X-Correlation-Id</header></expose-headers>
    </cors>
    <rate-limit calls="300" renewal-period="60" />
    <set-header name="X-Forwarded-By" exists-action="override"><value>apim-open-prontuario</value></set-header>
    <base />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
''', '__ORIGEM_FRONTEND__', frontendOrigin)
  }
}

resource produto 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'frontend'
  properties: {
    displayName: 'Frontend Open Prontuário'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource produtoApi 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: produto
  name: api.name
}

resource assinatura 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apim
  name: 'spa-frontend'
  properties: {
    displayName: 'SPA do frontend'
    scope: produto.id
    state: 'active'
  }
}

output gatewayUrl string = '${apim.properties.gatewayUrl}/api'
