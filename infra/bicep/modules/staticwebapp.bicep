param location string
param nome string

// Tier Free; o conteúdo é publicado pelo workflow do repositório do frontend
// (deployment token) ou com `swa deploy` — ver docs/DEPLOY.md.
resource site 'Microsoft.Web/staticSites@2023-12-01' = {
  name: nome
  location: location
  sku: { name: 'Free', tier: 'Free' }
  properties: {}
}

output hostname string = site.properties.defaultHostname
output nome string = site.name
