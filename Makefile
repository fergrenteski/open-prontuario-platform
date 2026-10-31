.PHONY: up down logs ps e2e lint-contratos publish

BFF_URL ?= http://localhost:3000/api

.env:
	cp .env.example .env

up: .env ## Sobe tudo com build
	docker compose up --build -d

down: ## Derruba e apaga os volumes
	docker compose down -v

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

e2e: ## Smoke test ponta a ponta contra o BFF
	node scripts/e2e-smoke.mjs $(BFF_URL)

lint-contratos: ## Valida OpenAPI (Redocly) e AsyncAPI
	npx -y @redocly/cli@1.34.5 lint docs/contracts/*.openapi.yaml
	npx -y @asyncapi/cli@2.16.0 validate docs/contracts/asyncapi.yaml

publish: ## make publish USER=<dockerhub-user> TAG=v1 (faça docker login antes)
	./scripts/docker-publish.sh $(USER) $(TAG)
