#!/usr/bin/env bash
# Liga, desliga e testa o Open Prontuário na Azure com um comando.
#
#   ./scripts/azure.sh subir      cria ou atualiza tudo (~20 min na 1ª vez, por causa do APIM)
#   ./scripts/azure.sh status     mostra se está no ar e as URLs
#   ./scripts/azure.sh testar     roda o smoke test E2E contra o API Gateway
#   ./scripts/azure.sh desligar   apaga o resource group inteiro: custo zero
#
# Configuração em .env.azure (fora do git), a partir de .env.azure.example.
# Pré-requisitos: az login, imagens publicadas no Docker Hub, JDK 17 e Node 20+.
set -euo pipefail

PLATAFORMA="$(cd "$(dirname "$0")/.." && pwd)"
RAIZ="$(cd "$PLATAFORMA/.." && pwd)"
ENV_FILE="$PLATAFORMA/.env.azure"

[[ -f "$ENV_FILE" ]] || { echo "Crie $ENV_FILE a partir de .env.azure.example."; exit 1; }

# Segredos que faltam são gerados uma vez e guardados no .env.azure.
gerar() { grep -q "^$1=" "$ENV_FILE" || echo "$1=$2" >> "$ENV_FILE"; }
gerar INTERNAL_API_KEY "$(openssl rand -hex 32)"
gerar JWT_SECRET "$(openssl rand -hex 32)"
gerar SQL_ADMIN_PASSWORD "Op$(openssl rand -hex 16)!a"

set -a; source "$ENV_FILE"; set +a
: "${DOCKERHUB_USER:?defina DOCKERHUB_USER no .env.azure}"
: "${MONGODB_URI:?defina MONGODB_URI no .env.azure}"
: "${APIM_EMAIL:?defina APIM_EMAIL no .env.azure}"
RG="${RG:-rg-openprontuario}"
LOCATION="${LOCATION:-brazilsouth}"
IMAGE_TAG="${IMAGE_TAG:-v1}"

saida() { az deployment group show -g "$RG" -n main --query "properties.outputs.$1.value" -o tsv; }

ligado() { [[ "$(az group exists -n "$RG")" == "true" ]]; }

chave_apim() {
  local id
  id=$(az apim list -g "$RG" --query "[0].id" -o tsv)
  az rest --method post --uri "$id/subscriptions/spa-frontend/listSecrets?api-version=2023-09-01-preview" --query primaryKey -o tsv
}

# API Management apagado fica 48 h em soft-delete e bloqueia o mesmo nome.
purgar_apim() {
  az apim deletedservice list --query "[?starts_with(name,'apim-openpront')].[name,location]" -o tsv |
    while IFS=$'\t' read -r nome regiao; do
      echo "==> Purgando APIM apagado $nome"
      az apim deletedservice purge --service-name "$nome" --location "$regiao"
    done
}

subir() {
  echo "==> Resource group $RG ($LOCATION)"
  az group create -n "$RG" -l "$LOCATION" -o none
  purgar_apim

  echo "==> Infraestrutura (Bicep): a 1ª vez leva ~20 min"
  az deployment group create -g "$RG" -n main -o none \
    --template-file "$PLATAFORMA/infra/bicep/main.bicep" \
    --parameters location="$LOCATION" dockerHubUser="$DOCKERHUB_USER" imageTag="$IMAGE_TAG" \
                 mongodbUri="$MONGODB_URI" sqlAdminPassword="$SQL_ADMIN_PASSWORD" \
                 internalApiKey="$INTERNAL_API_KEY" jwtSecret="$JWT_SECRET" \
                 apimPublisherEmail="$APIM_EMAIL" authMode=dev

  echo "==> Function (Visão Agregada)"
  (cd "$RAIZ/open-prontuario-fn-visao-agregada" &&
    ./mvnw -q clean package azure-functions:deploy -DskipTests \
      -DfunctionAppName="$(saida functionAppName)" -DfunctionResourceGroup="$RG" -DfunctionRegion="$LOCATION")

  echo "==> Frontend (Static Web Apps)"
  local gateway swa
  gateway=$(saida apiGatewayUrl)
  swa=$(saida staticWebAppName)
  (cd "$RAIZ/open-prontuario-frontend" && npm ci --silent &&
    VITE_API_BASE_URL="$gateway" VITE_APIM_SUBSCRIPTION_KEY="$(chave_apim)" VITE_AUTH_MODE=dev npm run build --silent &&
    npx -y @azure/static-web-apps-cli@2.0.2 deploy ./dist --env production \
      --deployment-token "$(az staticwebapp secrets list -n "$swa" --query properties.apiKey -o tsv)")

  status
}

status() {
  if ! ligado; then
    echo "Desligado: o resource group $RG não existe (custo zero)."
    return
  fi
  az deployment group show -g "$RG" -n main -o yaml --query "properties.outputs.{
    frontend: frontendUrl.value, apiGateway: apiGatewayUrl.value, bffSwagger: bffSwaggerUrl.value,
    msFilaSwagger: msFilaSwaggerUrl.value, msProntuarioSwagger: msProntuarioSwaggerUrl.value,
    function: functionUrl.value }"
}

testar() {
  ligado || { echo "Desligado: rode ./scripts/azure.sh subir"; exit 1; }
  APIM_KEY="$(chave_apim)" node "$PLATAFORMA/scripts/e2e-smoke.mjs" "$(saida apiGatewayUrl)"
}

desligar() {
  ligado || { echo "Já está desligado."; return; }
  read -r -p "Apagar TODOS os recursos de $RG? Os dados do Azure SQL são perdidos (o Atlas fica). [s/N] " ok
  [[ "$ok" == "s" || "$ok" == "S" ]] || exit 1
  echo "==> Apagando $RG (~10 min)"
  az group delete -n "$RG" --yes
  purgar_apim
  echo "Desligado. Para ligar de novo: ./scripts/azure.sh subir"
}

case "${1:-}" in
  subir|status|testar|desligar) "$1" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
