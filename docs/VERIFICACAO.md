# Relatório de verificação

O que foi executado de verdade em 31/10/2026 numa máquina macOS arm64 (JDK 17, Node 24, Docker Desktop com 4 GB) e o que **não** foi.

## Testes de cada repositório (rodados novamente pelo agente principal após a entrega de cada subagente)

| Repositório | Comando | Resultado | Tag |
|---|---|---|---|
| `open-prontuario-ms-fila-sql` | `./mvnw verify` | 138 testes, 0 falhas, 0 pulados (domínio, casos de uso, MockMvc, Service Bus mockado, ArchUnit, contrato, JaCoCo ≥ 80%) | `v1.0.0` |
| | `./mvnw verify -Pintegration` | +8 IT com SQL Server 2022 (Testcontainers), 0 falhas (executado pelo subagente) | |
| `open-prontuario-ms-prontuario-mongo` | `./mvnw verify` | 105 testes, 0 falhas, 0 pulados | `v1.0.0` |
| | `./mvnw verify -Pintegration` | +7 IT com `mongo:7`, 0 falhas (executado pelo subagente) | |
| `open-prontuario-fn-visao-agregada` | `./mvnw verify` | 64 testes, 0 falhas, 0 pulados | `v1.0.0` |
| | `./mvnw verify -Pintegration` | +9 IT (Mongo + servidor HTTP local), 0 falhas (executado pelo subagente) | |
| `open-prontuario-bff` | `npm test` | 17 suítes, 138 testes, 0 falhas; cobertura 99,8%; dependency-cruiser sem violações; `npm run lint` limpo | `v1.0.0` |
| `open-prontuario-frontend` | `npm test` · `npm run lint` · `npm run build` | 25 arquivos, 124 testes, 0 falhas; cobertura 99,6%; lint e build ok | `v1.0.0` |

Em cada repositório foi provado que o teste de arquitetura **falha** com uma violação proposital (não commitada) — detalhes no README de cada um. Todos os commits têm mensagem Conventional Commits em português e terminam com o trailer `Co-Authored-By`.

`docker build` foi executado com sucesso pelos subagentes nos cinco repositórios, com o container respondendo ao health check (as imagens foram apagadas depois por falta de espaço em disco).

## Integração ponta a ponta

Por falta de espaço em disco (≈ 3 GB livres), o `docker compose up --build` completo **não** foi executado. A integração foi feita com a **infraestrutura do compose em Docker** e os **serviços rodando direto no host**:

```bash
docker compose up -d mssql mssql-init servicebus-emulator mongo azurite
```

- MS Fila e MS Prontuário: `java -jar target/*.jar` com as variáveis da `CONVENCOES.md` §7 apontando para `localhost`.
- Function: `func start --port 7071` em `target/azure-functions/fn-visao-agregada`, com `AzureWebJobsStorage=UseDevelopmentStorage=true` (Azurite) e `ServiceBusConnection` do emulador.
- BFF: `node dist/bootstrap/main.js` com `AUTH_MODE=dev`.

Resultado de `node scripts/e2e-smoke.mjs` (executado **duas vezes seguidas**, ambas verdes):

```
✔ 1. BFF saudável
✔ 2. tokens dev emitidos para paciente, atendente, profissional e gestor
✔ 3. estado anterior do paciente pac-101 limpo
✔ 4. unidades próximas (MS Fila + Function): ubs-03 1.0 km, upa-02 6.0 km, upa-01 6.1 km
✔ 5. paciente avisou chegada (A_CAMINHO, prioridade preliminar MUITO_URGENTE)
✔ 6. evento PACIENTE_A_CAMINHO: Function recalculou a visão (a caminho=1, presentes=0, nível=BAIXO)
✔ 7. atendente confirmou a chegada (AGUARDANDO)
✔ 8. evento PACIENTE_CHEGOU: Function recalculou a visão (a caminho=0, presentes=1, nível=BAIXO)
✔ 9. profissional sem consentimento recebe 403 CONSENTIMENTO_AUSENTE
✔ 10. paciente concedeu consentimento
✔ 11. profissional leu o prontuário pront-001 (alergias: dipirona)
✔ 12. acesso registrado na auditoria com o consentimentoId
✔ 13. /aggregated-data uniu ms-fila-sql(30ms) + ms-prontuario-mongo(28ms) + fn-visao-agregada(17ms)
✔ 14. atendimento iniciado; transição inválida devolve 409
✔ 15. registro encerrado (FINALIZADO, motivo ATENDIDO)
✔ 16. eventos ATENDIMENTO_INICIADO e PACIENTE_REMOVIDO: Function recalculou a visão
✔ 17. revogação tem efeito imediato (403 na leitura seguinte)
✔ 18. CRUD de unidade pelo gestor (criar, editar, ler, remover)
✔ 19. perfil errado é barrado pelo BFF (403)
E2E OK — 19 verificações.
```

Também verificado manualmente:

- **Degradação graciosa:** com a Function parada, `GET /api/aggregated-data?unidadeId=upa-01` respondeu 200 com `meta.degraded = true` e `falhas = [{fonte: fn-visao-agregada, motivo: indisponivel}]`.
- **Frontend contra o BFF real** (Vite dev + navegador): login como Carla (atendente), seleção da UPA Boa Vista com as lotações do MS Fila, fila ordenada por prioridade com pacientes a caminho e o selo "Autorizado" vindo do MS Prontuário, indicadores da Function, e "Confirmar chegada" atualizando a fila e os indicadores no polling seguinte.

### `docker compose up --build` completo

Depois de liberar espaço em disco, `make up` construiu as 5 imagens e subiu os 11 containers (todos `healthy` em ~20 s). `make e2e` passou nas **19 verificações**. Logo após a subida, a primeira tentativa recebeu 503 do MS Fila porque o Service Bus Emulator ainda estava criando o tópico; 30 s depois tudo passou.

## GitHub e Docker Hub

- Os 6 repositórios são públicos em `github.com/fergrenteski/open-prontuario-*`, com a tag `v1.0.0`. O CI (GitHub Actions) do primeiro push ficou verde nos 5 repositórios de código.
- Imagens `linux/amd64` publicadas: `fergrenteski/pjbl-bff:v1`, `pjbl-ms-fila-sql:v1`, `pjbl-ms-prontuario-mongo:v1`, `pjbl-fn-visao-agregada:v1`, `pjbl-frontend:v1`.

## Nuvem (Azure + MongoDB Atlas)

Implantado com `./scripts/azure.sh subir` na assinatura Azure for Students (`brazilsouth`); MongoDB Atlas M0 em São Paulo (AWS `SA_EAST_1`, região Azure indisponível para M0). `./scripts/azure.sh testar` passou nas **19 verificações** contra o API Gateway, com Azure SQL, Service Bus Standard, Function (Flex Consumption) e Atlas reais:

```
E2E smoke — https://apim-openpront-kuuqj6ka4e67k.azure-api.net/api
  ✔ 13. /aggregated-data uniu ms-fila-sql(113ms) + ms-prontuario-mongo(86ms) + fn-visao-agregada(19ms)
  ...
E2E OK — 19 verificações.
```

Também verificado no navegador: frontend no Static Web Apps → login como Carla → unidades da lotação → fila da UPA Boa Vista com os indicadores da Function. Todos os links da seção "Links da entrega" do arc42 respondem 200 (o gateway responde 401 sem a subscription key, como esperado).

Problemas encontrados no deploy e corrigidos:

- **Function:** o plano Y1 (Linux Consumption) tem cota zero no Azure for Students; o Bicep passou a usar **Flex Consumption (FC1)** e o deploy passou a ser por zip.
- **API Management:** a política da API falhava com `PreconditionFailed` por escrita concorrente com as operações; a política agora depende das operações.
- **Partida a frio:** tudo escala a zero e um serviço Java leva ~30 s para acordar. O timeout do BFF em nuvem subiu para 45 s e o do frontend para 60 s; `./scripts/azure.sh acordar` aquece tudo antes de apresentar.
- **Static Web Apps:** o CLI baixa um binário .NET x86_64 que não roda em Mac ARM sem Rosetta; o `azure.sh` roda o deploy dentro de um container `node:20`.

## Ajustes descobertos na integração

- O **Service Bus Emulator** aceita no máximo `DefaultMessageTimeToLive = PT1H` e `DuplicateDetectionHistoryTimeWindow = PT5M`. O `servicebus/Config.json` usa esses limites; o Bicep (produção) mantém 1 dia e 10 minutos, como no arc42.
- Bind mount de um arquivo único guarda o inode antigo: depois de editar o `Config.json`, use `docker compose up -d --force-recreate servicebus-emulator`.
- O gatilho Java da Function exige a propriedade AMQP `correlationId` em toda mensagem; o MS Fila foi ajustado para sempre preenchê-la (gera UUID se não houver).

## Não verificado

- Gatilho da DLQ contra o emulador (coberto por testes unitários).
- Modo `entra` (Microsoft Entra ID) em nuvem: a demonstração usa `authMode=dev` com as personas.
- `./scripts/azure.sh desligar` seguido de `subir` (apagar e recriar tudo) não foi exercitado para não derrubar o ambiente da entrega.
- Geração do PDF (pandoc não instalado; comando com Docker em `DEPLOY.md`).
