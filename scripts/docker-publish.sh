#!/usr/bin/env bash
# Build + tag + push das imagens no Docker Hub, no formato exigido pelo PJBL:
#   <usuario>/pjbl-<imagem>:<tag>
# O Docker Hub não aceita namespaces aninhados (<usuario>/pjbl/<imagem>), então
# "pjbl" vira prefixo do nome do repositório.
#
# Uso: ./scripts/docker-publish.sh <usuario-dockerhub> <tag> [--sem-push]
# Pré-requisito: `docker login` feito por você (o script não faz login).
set -euo pipefail

USUARIO="${1:?uso: $0 <usuario-dockerhub> <tag> [--sem-push]}"
TAG="${2:?uso: $0 <usuario-dockerhub> <tag> [--sem-push]}"
SEM_PUSH="${3:-}"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
# Imagens publicadas na arquitetura usada pelo Azure Container Apps.
PLATAFORMA="${PLATAFORMA:-linux/amd64}"

# Compatível com o bash 3.2 do macOS (sem arrays associativos).
IMAGENS="bff ms-fila-sql ms-prontuario-mongo fn-visao-agregada frontend"

for nome in $IMAGENS; do
  repo="$RAIZ/open-prontuario-$nome"
  imagem="$USUARIO/pjbl-$nome:$TAG"
  echo "==> $imagem ($repo)"
  docker buildx build --platform "$PLATAFORMA" -t "$imagem" --load "$repo"
  if [[ "$SEM_PUSH" != "--sem-push" ]]; then
    docker push "$imagem"
  fi
done

echo "Pronto: $(for n in $IMAGENS; do printf '%s ' "$USUARIO/pjbl-$n:$TAG"; done)"
