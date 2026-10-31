# Deploy em nuvem (Azure + MongoDB Atlas + Docker Hub)

Este é o passo a passo para colocar o Open Prontuário no ar com URLs públicas, como o vídeo do PJBL exige. **Todos os passos usam as suas credenciais e são feitos por você** (Azure, Atlas, Docker Hub e GitHub). Nada aqui foi executado pela automação que gerou o projeto.

Custo: Container Apps, Functions e API Management em planos de consumo; Azure SQL na oferta gratuita; Atlas M0 e Static Web Apps Free. O **Service Bus Standard** é cobrado por hora (centavos de dólar por dia). Apague o resource group ao fim do semestre (passo 9).

## 0. Pré-requisitos

- Azure CLI logado na assinatura Azure for Students: `az login`
- Docker Desktop, conta no Docker Hub
- Conta no MongoDB Atlas
- Node 20+, JDK 17, Maven (ou o `mvnw` dos repositórios)
- Os 6 repositórios clonados lado a lado

## 1. MongoDB Atlas (M0)

1. Crie um cluster **M0** (região mais próxima, ex.: São Paulo).
2. *Database Access* → crie um usuário com permissão `readWriteAnyDatabase` (senha forte, só para este projeto).
3. *Network Access* → adicione `0.0.0.0/0`. Container Apps e Functions em plano de consumo não têm IP de saída fixo; a proteção fica por conta do usuário e senha + TLS. Esse risco está registrado no arc42 (seção 11).
4. *Connect → Drivers* → copie a connection string `mongodb+srv://<usuario>:<senha>@<cluster>.mongodb.net/?retryWrites=true&w=majority`.

Os bancos `prontuario` e `visao` e os índices são criados automaticamente pelos serviços na primeira execução.

## 2. Imagens no Docker Hub

O Docker Hub só aceita um nível de namespace, então as imagens seguem o formato `<usuario>/pjbl-<servico>:<tag>`.

```bash
docker login
```

```bash
cd open-prontuario-platform && ./scripts/docker-publish.sh <usuario-dockerhub> v1
```

O script gera as imagens para `linux/amd64` (arquitetura do Azure Container Apps) e publica `pjbl-bff`, `pjbl-ms-fila-sql`, `pjbl-ms-prontuario-mongo`, `pjbl-fn-visao-agregada` e `pjbl-frontend`. Só as três primeiras são usadas pelo Bicep; as outras duas ficam como entrega no Docker Hub. Cada imagem precisa de alguns GB livres em disco para ser construída.

## 3. Infraestrutura Azure (Bicep)

```bash
az group create -n rg-openprontuario -l brazilsouth
```

```bash
az deployment group create -g rg-openprontuario \
  --template-file open-prontuario-platform/infra/bicep/main.bicep \
  --parameters dockerHubUser=<usuario-dockerhub> imageTag=v1 \
               mongodbUri='<connection string do Atlas>' \
               sqlAdminPassword='<senha forte>' \
               internalApiKey="$(openssl rand -hex 32)" \
               jwtSecret="$(openssl rand -hex 32)" \
               apimPublisherEmail=<seu-email> \
               authMode=dev
```

- `authMode=dev` usa as personas de demonstração (João, Maria, Carla, Dr. Paulo, Lúcia). Para usar o Microsoft Entra ID, passe `authMode=entra entraTenantId=<tenant> entraAudience=<client id da API>` e siga o README do BFF.
- O API Management Consumption leva de 5 a 15 minutos para ser criado.
- Se a assinatura de estudante bloquear `brazilsouth`, use `eastus2` (e passe `location=eastus2`).

Guarde os *outputs*:

```bash
az deployment group show -g rg-openprontuario -n main --query properties.outputs -o table
```

Os outputs são `frontendUrl`, `apiGatewayUrl`, `bffSwaggerUrl`, `msFilaSwaggerUrl`, `msProntuarioSwaggerUrl`, `functionUrl`, `functionAppName`, `staticWebAppName`, `sqlServerFqdn` e `serviceBusNamespace`.

## 4. Banco do MS Fila

O Bicep cria o database `openprontuario`. As tabelas e o seed são criados pelo Flyway na primeira subida do MS Fila. Se o primeiro acesso falhar por *timeout* (o banco serverless acorda do auto-pause), espere 1 minuto e acesse de novo.

## 5. Function (Visão Agregada)

```bash
cd open-prontuario-fn-visao-agregada
```

```bash
./mvnw clean package azure-functions:deploy -DskipTests \
  -DfunctionAppName=<output functionAppName> \
  -DfunctionResourceGroup=rg-openprontuario \
  -DfunctionRegion=brazilsouth
```

As variáveis de ambiente (Service Bus, Mongo, URL do MS Fila, chave interna) já foram configuradas pelo Bicep.

## 6. Frontend (Static Web Apps)

Pegue a subscription key do API Management (ela identifica o cliente para o rate limit e fica embutida no bundle; não é segredo):

```bash
az rest --method post --uri "$(az apim show -g rg-openprontuario -n $(az apim list -g rg-openprontuario --query [0].name -o tsv) --query id -o tsv)/subscriptions/spa-frontend/listSecrets?api-version=2023-09-01-preview" --query primaryKey -o tsv
```

Gere o build apontando para o gateway e publique:

```bash
cd open-prontuario-frontend && npm ci && VITE_API_BASE_URL=<output apiGatewayUrl> VITE_APIM_SUBSCRIPTION_KEY=<chave> VITE_AUTH_MODE=dev npm run build
```

```bash
npx @azure/static-web-apps-cli deploy ./dist --env production \
  --deployment-token "$(az staticwebapp secrets list -n <output staticWebAppName> --query properties.apiKey -o tsv)"
```

## 7. Verificação ponta a ponta em nuvem

```bash
cd open-prontuario-platform && APIM_KEY=<chave> node scripts/e2e-smoke.mjs <output apiGatewayUrl>
```

Os serviços escalam a zero: a primeira chamada pode demorar ~30 s (cold start). Se o script falhar por *timeout* logo no início, rode de novo.

## 8. GitHub e entrega

1. Crie os 6 repositórios **públicos** e faça push (cada repositório já tem `main` e a tag `v1.0.0`):

   ```bash
   gh repo create fergrenteski/<repo> --public --source=. --push && git push --tags
   ```

2. Preencha a seção "Links da entrega" do `docs/arc42_open_prontuario_pjbl.md` com os outputs do passo 3.
3. Tire os prints de `docs/prints/CHECKLIST.md` e grave o vídeo seguindo `docs/video/ROTEIRO.md`.
4. Gere o PDF do arc42 (o pandoc não está instalado na máquina de desenvolvimento; use a imagem Docker):

   ```bash
   cd open-prontuario-platform/docs && docker run --rm -v "$PWD":/data pandoc/latex:3.6 arc42_open_prontuario_pjbl.md -o arc42_open_prontuario_pjbl.pdf --toc -V geometry:margin=2cm
   ```

## 9. Limpeza (fim do semestre)

```bash
az group delete -n rg-openprontuario --yes --no-wait
```

Apague também o cluster no Atlas e, se quiser, as imagens no Docker Hub.
