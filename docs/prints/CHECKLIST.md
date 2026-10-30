# Prints obrigatórios da entrega

Os prints só existem depois do deploy em nuvem (`docs/DEPLOY.md`). Salve as imagens nesta pasta com os nomes abaixo e insira-as no PDF do arc42. **Em todos os prints a barra de endereço com a URL de nuvem deve estar visível.**

| Arquivo | O que mostrar | URL (output do Bicep) |
|---|---|---|
| `01-swagger-bff.png` | Swagger UI do BFF com a lista de rotas e `GET /aggregated-data` expandido e executado (resposta 200 com `meta.fontes`) | `bffSwaggerUrl` |
| `02-swagger-ms-fila.png` | Swagger UI do MS Fila com Unidades, Lotações e Fila | `msFilaSwaggerUrl` |
| `03-swagger-ms-prontuario.png` | Swagger UI do MS Prontuário com Prontuário, Consentimento e Auditoria | `msProntuarioSwaggerUrl` |
| `04-eventos-asyncapi.png` | AsyncAPI renderizado (ex.: https://studio.asyncapi.com colando `docs/contracts/asyncapi.yaml`) | link do arquivo no GitHub |
| `05-frontend-paciente.png` | Área do paciente: UPAs próximas (layout celular) | `frontendUrl` |
| `06-frontend-fila.png` | Área do atendente: fila priorizada com pacientes presentes e a caminho | `frontendUrl` |
| `07-frontend-prontuario.png` | Prontuário aberto com consentimento e a auditoria vista pelo paciente | `frontendUrl` |
| `08-frontend-indicadores.png` | Indicadores do gestor com o JSON do `/aggregated-data` e as fontes | `frontendUrl` |
| `09-api-gateway.png` | Portal Azure → API Management → APIs → Open Prontuário (operações) **e** Analytics com requisições | `apiGatewayUrl` |
| `10-service-bus.png` | Portal → Service Bus → tópico `eventos-atendimento` → subscription `agregador` (contagem de mensagens / DLQ) | portal |
| `11-function-monitor.png` | Portal → Function App → `EventoFilaFunction` → Monitor com execuções bem-sucedidas | portal |
| `12-docker-hub.png` | Docker Hub com as imagens `pjbl-bff`, `pjbl-ms-fila-sql`, `pjbl-ms-prontuario-mongo` e a tag | hub.docker.com |
| `13-github-ci.png` | Aba Actions de um repositório com o CI verde (testes + arquitetura) | github.com |
| `14-atlas.png` | MongoDB Atlas → Browse Collections (`prontuario.auditoria` ou `visao.visao_agregada`) | cloud.mongodb.com |
| `15-azure-sql.png` | Azure SQL → Query editor com `SELECT * FROM registros_fila` | portal |
