# Convenções compartilhadas entre os serviços

Este arquivo é a fonte de verdade para tudo o que **mais de um repositório** precisa concordar: portas, headers, formato de erro, variáveis de ambiente, identidades e dados de seed. Os contratos HTTP estão nos arquivos `*.openapi.yaml` e o contrato de eventos em `asyncapi.yaml`.

## 1. Serviços, portas e prefixos

| Serviço | Repo | Porta local | Prefixo | Exposto publicamente? |
|---|---|---|---|---|
| Frontend (SPA) | `open-prontuario-frontend` | 5173 (dev) / 8080 (nginx) | `/` | sim (Static Web Apps) |
| BFF | `open-prontuario-bff` | 3000 | `/api` | sim, **somente via API Gateway** |
| MS Fila (Azure SQL) | `open-prontuario-ms-fila-sql` | 8081 | `/` | Swagger/health públicos; demais rotas exigem `X-Internal-Key` |
| MS Prontuário (MongoDB) | `open-prontuario-ms-prontuario-mongo` | 8082 | `/` | idem |
| Function Visão Agregada | `open-prontuario-fn-visao-agregada` | 7071 | `/api` | idem |

O frontend fala **apenas** com o BFF (via Gateway em nuvem). Microserviços e Function só são chamados pelo BFF (e entre si nas rotas `/internal/**`).

## 2. Headers propagados

| Header | Quem envia | Significado |
|---|---|---|
| `Authorization: Bearer <jwt>` | Front → BFF | Token do usuário (Entra ID ou dev). **Só o BFF valida JWT.** |
| `X-Internal-Key` | BFF → serviços; serviço → serviço; Function → MS Fila | Segredo compartilhado (`INTERNAL_API_KEY`). Sem ele (ou errado) → `401`. Exceções: `/swagger-ui/**`, `/v3/api-docs/**`, `/actuator/health`, `/health`, `/api/docs`. |
| `X-User-Id` | BFF → serviços | `oid` do usuário autenticado (ex.: `pac-101`). Os serviços **nunca** aceitam identificador de usuário no corpo/query para decidir "quem sou eu". |
| `X-User-Roles` | BFF → serviços | Perfis separados por vírgula: `PACIENTE`, `ATENDENTE`, `PROFISSIONAL`, `GESTOR`. |
| `X-User-Name` | BFF → serviços | Nome de exibição (claim `name`). Usado pelo MS Fila para upsert do paciente no aviso de chegada. |
| `X-Correlation-Id` | todos | Gerado pelo BFF se ausente (UUID v4), propagado a todos os serviços, devolvido na resposta, colocado no MDC/log e no `correlationId` da mensagem do Service Bus; a Function o restaura antes de processar. |

Rotas `/internal/**` exigem apenas `X-Internal-Key` (não exigem `X-User-*`).

## 3. Autorização

- O **BFF** aplica a autorização por perfil (tabela de perfis em cada operação do `bff.openapi.yaml`, extensão `x-roles`). Perfil insuficiente → `403`.
- Os **serviços** aplicam as regras de negócio que dependem da identidade: lotação na unidade, titularidade do consentimento/prontuário, consentimento válido. Para isso leem `X-User-Id` e `X-User-Roles`. Ausência de `X-User-Id` numa rota de usuário → `401`.

## 4. Formato de erro (RFC 9457 — `application/problem+json`)

```json
{
  "type": "https://openprontuario.dev/erros/consentimento-invalido",
  "title": "Consentimento inválido",
  "status": 403,
  "detail": "O paciente não autorizou o compartilhamento do prontuário com esta unidade.",
  "instance": "/prontuarios/pac-101",
  "codigo": "CONSENTIMENTO_AUSENTE",
  "correlationId": "8f2c1e7a-4b6d-4c1f-9a3e-2d5b7c9e1f04"
}
```

| Situação | Status | `codigo` |
|---|---|---|
| Payload/parâmetro inválido | 400 | `REQUISICAO_INVALIDA` |
| Sem token / `X-Internal-Key` / `X-User-Id` | 401 | `NAO_AUTENTICADO` |
| Perfil sem permissão / não lotado (`AcessoNegadoException`) | 403 | `SEM_PERMISSAO` |
| Consentimento ausente, expirado ou revogado (`ConsentimentoInvalidoException`) | 403 | `CONSENTIMENTO_AUSENTE` |
| Recurso inexistente (`RecursoNaoEncontradoException`) | 404 | `RECURSO_NAO_ENCONTRADO` |
| Transição de estado inválida (`TransicaoInvalidaException`) | 409 | `TRANSICAO_INVALIDA` |
| Registro ativo duplicado na unidade | 409 | `REGISTRO_ATIVO_DUPLICADO` |
| Consentimento ativo já existente | 409 | `CONSENTIMENTO_DUPLICADO` |
| Dependência indisponível (inclui falha ao gravar auditoria) | 503 | `DEPENDENCIA_INDISPONIVEL` |
| Todas as fontes do `/aggregated-data` falharam | 502 | `AGREGACAO_FALHOU` |

Nunca devolver stack trace, SQL, nem dado clínico em erro.

## 5. Datas, IDs e enums

- Datas: ISO-8601 com offset (`OffsetDateTime` no Java, `string` `date-time` no contrato). Servidor gera os horários; o cliente nunca envia `horario*`.
- IDs gerados pelo servidor: `UUID` em string, exceto os IDs de seed abaixo (strings legíveis).
- Enums (valores exatos): `Prioridade` = `EMERGENCIA, MUITO_URGENTE, URGENTE, POUCO_URGENTE, NAO_URGENTE` (ordem = gravidade decrescente); `StatusFila` = `A_CAMINHO, AGUARDANDO, EM_ATENDIMENTO, FINALIZADO`; `MotivoSaida` = `ATENDIDO, DESISTENCIA, ENCAMINHADO`; `TipoUnidade` = `UBS, UPA`; `PerfilUsuario` = `PACIENTE, ATENDENTE, PROFISSIONAL, GESTOR`; `NivelCongestionamento` = `BAIXO, MEDIO, ALTO`.

## 6. Regras de domínio compartilhadas (resumo do arc42)

- **Máquina de estados** do `RegistroFila`: `avisar → A_CAMINHO`; `A_CAMINHO → AGUARDANDO` (confirmarChegada); `AGUARDANDO → EM_ATENDIMENTO` (iniciarAtendimento); `EM_ATENDIMENTO → FINALIZADO` só com `ATENDIDO`; `A_CAMINHO → FINALIZADO` só com `DESISTENCIA`; `AGUARDANDO → FINALIZADO` com `DESISTENCIA` ou `ENCAMINHADO`; alterarPrioridade só em `A_CAMINHO`/`AGUARDANDO`. Qualquer outra → `TransicaoInvalidaException` (409).
- Um paciente só pode ter **um registro ativo** (status ≠ `FINALIZADO`) por unidade → 409 `REGISTRO_ATIVO_DUPLICADO`.
- **Ordenação da fila** (`OrdenacaoFilaPolicy`): prioridade (mais grave primeiro), desempate por `horarioChegada` (ou `horarioAviso` se ainda a caminho), mais antigo primeiro. `FINALIZADO` não aparece na fila.
- **Classificação preliminar** (`ClassificacaoPreliminarPolicy`), por sintoma (comparação sem acento e sem caixa, por "contém"):
  - `EMERGENCIA`: "parada", "inconsciente", "convulsao", "hemorragia"
  - `MUITO_URGENTE`: "dor no peito", "falta de ar", "desmaio", "avc"
  - `URGENTE`: "febre alta", "vomito", "fratura", "dor intensa"
  - `POUCO_URGENTE`: "febre", "dor", "tontura"
  - senão `NAO_URGENTE`. Vale o nível mais grave encontrado.
- **Consentimento** (Open Finance): `conceder(pacienteId, unidadeId, validadeDias, agora)`, validade padrão **3 dias**, mínimo 1, máximo **365**; `estaValido(agora)` = `ativo && revogadoEm == null && agora < expiraEm`; `revogar(agora)` marca `ativo=false`, `revogadoEm=agora` (só o titular); `renovar(validadeDias, agora)` só se ainda válido. Um consentimento válido por (paciente, unidade) → 409 `CONSENTIMENTO_DUPLICADO`.
- **Consulta de prontuário por profissional** (fail-closed): (1) lotado na unidade? senão 403 `SEM_PERMISSAO`; (2) consentimento válido? senão 403 `CONSENTIMENTO_AUSENTE`; (3) lê prontuário (404 se não existe); (4) grava `LogAuditoria` (prontuarioId, consentimentoId, usuarioId, unidadeId, acessadoEm); **se a gravação falhar, nada é devolvido → 503**; (5) devolve.
- **Auditoria** é append-only. Paciente titular vê todos os acessos ao próprio prontuário; GESTOR vê só os acessos cuja `unidadeId` está entre as unidades em que ele é lotado; outros perfis → 403.
- **Visão agregada** (Function), recalculada a partir do estado: `totalACaminho` = nº com status `A_CAMINHO`; `totalPresente` = nº com status `AGUARDANDO`; `tempoMedioEsperaMin` = média arredondada de (`horarioInicioAtendimento − horarioChegada`) em minutos dos registros com `horarioInicioAtendimento` nas últimas 2 h (0 se nenhum); `nivelCongestionamento` = `ALTO` se (`totalPresente + totalACaminho` ≥ 15 ou `tempoMedioEsperaMin` ≥ 60), `MEDIO` se (≥ 6 ou ≥ 30), senão `BAIXO`.
- **Distância** das unidades próximas: fórmula de Haversine no domínio (`UnidadeSaude.calcularDistancia(lat, lon)`), sem Azure Maps (ADR: minimização de dados e custo).

## 7. Variáveis de ambiente (nomes exatos)

| Repo | Variável | Exemplo local (compose) |
|---|---|---|
| ms-fila-sql | `PORT` | `8081` |
| | `DB_URL` | `jdbc:sqlserver://mssql:1433;databaseName=openprontuario;encrypt=true;trustServerCertificate=true` |
| | `DB_USER` / `DB_PASSWORD` | `sa` / `<senha>` |
| | `SERVICEBUS_CONNECTION_STRING` | `Endpoint=sb://servicebus-emulator;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;` |
| | `SERVICEBUS_TOPIC` | `eventos-atendimento` |
| | `INTERNAL_API_KEY` | `dev-internal-key` |
| ms-prontuario-mongo | `PORT` | `8082` |
| | `MONGODB_URI` | `mongodb://mongo:27017` |
| | `MONGODB_DATABASE` | `prontuario` |
| | `MS_FILA_URL` | `http://ms-fila-sql:8081` |
| | `INTERNAL_API_KEY` | `dev-internal-key` |
| fn-visao-agregada | `ServiceBusConnection` | (mesma do MS Fila) |
| | `SERVICEBUS_TOPIC` / `SERVICEBUS_SUBSCRIPTION` | `eventos-atendimento` / `agregador` |
| | `MONGODB_URI` / `MONGODB_DATABASE` | `mongodb://mongo:27017` / `visao` |
| | `MS_FILA_URL` | `http://ms-fila-sql:8081` |
| | `INTERNAL_API_KEY` | `dev-internal-key` |
| | `AzureWebJobsStorage` | Azurite (`UseDevelopmentStorage=true` não funciona em container; usar connection string completa do Azurite) |
| bff | `PORT` | `3000` |
| | `AUTH_MODE` | `dev` ou `entra` |
| | `JWT_SECRET` | segredo HS256 (modo dev) |
| | `ENTRA_TENANT_ID` / `ENTRA_AUDIENCE` | modo entra |
| | `ALLOW_DEV_AUTH_IN_PRODUCTION` | `false` (padrão). Com `NODE_ENV=production` e `AUTH_MODE=dev`, o BFF só sobe se esta flag for `true` |
| | `MS_FILA_URL` / `MS_PRONTUARIO_URL` / `FN_VISAO_URL` | `http://ms-fila-sql:8081` / `http://ms-prontuario-mongo:8082` / `http://fn-visao-agregada:80` |
| | `INTERNAL_API_KEY` | `dev-internal-key` |
| | `CORS_ORIGINS` | `http://localhost:5173,http://localhost:8080` |
| | `UPSTREAM_TIMEOUT_MS` | `3000` |
| frontend | `VITE_API_BASE_URL` | `http://localhost:3000/api` |
| | `VITE_AUTH_MODE` | `dev` ou `entra` |
| | `VITE_ENTRA_CLIENT_ID` / `VITE_ENTRA_TENANT_ID` / `VITE_ENTRA_API_SCOPE` | modo entra |

## 8. Identidades e seed (iguais em todos os repos)

Personas do modo dev (`POST /api/auth/dev-token` no BFF):

| `usuarioId` (`oid`) | Nome | Perfis | Lotações |
|---|---|---|---|
| `pac-101` | João Pereira | PACIENTE | — |
| `pac-102` | Maria Souza | PACIENTE | — |
| `usr-atendente-07` | Carla Mendes | ATENDENTE | `upa-01`, `upa-02` |
| `usr-prof-03` | Dr. Paulo Lima | PROFISSIONAL | `upa-01` |
| `usr-gestor-01` | Lúcia Andrade | GESTOR | `upa-01`, `upa-02`, `ubs-03` |

Unidades (MS Fila, migração Flyway de seed):

| id | nome | tipo | latitude | longitude |
|---|---|---|---|---|
| `upa-01` | UPA Boa Vista | UPA | -25.3866 | -49.2346 |
| `upa-02` | UPA Cajuru | UPA | -25.4486 | -49.2183 |
| `ubs-03` | UBS Mãe Curitibana | UBS | -25.4372 | -49.2700 |

Lotações (MS Fila): conforme a tabela de personas, ids `lot-1` … `lot-6`, perfil = perfil da persona.

Pacientes (MS Fila): `pac-101` João Pereira (cpf `11111111111`, cartaoSus `700000000000001`), `pac-102` Maria Souza (cpf `22222222222`, cartaoSus `700000000000002`).

Prontuários (MS Prontuário, seed na inicialização se a coleção estiver vazia):
- `pront-001` de `pac-101`: alergias `["dipirona"]`, medicações `["losartana 50mg"]`, atendimento `atd-900` em `ubs-03`, "Consulta de rotina - hipertensão controlada", `2026-06-14T10:30:00-03:00`.
- `pront-002` de `pac-102`: alergias `[]`, medicações `["metformina 850mg"]`, sem atendimentos.

Nenhum consentimento, registro de fila ou auditoria no seed (são criados no fluxo da demonstração).

## 9. Mensageria

- Tópico `eventos-atendimento`, subscription `agregador` (`maxDeliveryCount = 5`, `lockDuration = PT1M`, dead-lettering em expiração), DLQ `eventos-atendimento/Subscriptions/agregador/$DeadLetterQueue`.
- Mensagem: corpo JSON `EventoFilaMessage` (ver `asyncapi.yaml`), propriedades AMQP `messageId = eventoId`, `subject = tipo`, `correlationId`, `contentType = application/json`.
- O MS Fila publica **depois** de salvar. Falha de publicação é logada e **não** desfaz a operação (débito técnico: Transactional Outbox).
- A Function é idempotente: ignora `eventoId` já em `eventos_processados` (TTL 24 h) e recalcula a partir do estado lido em `GET /internal/fila/{unidadeId}/snapshot` do MS Fila.
- Mensagem inválida (JSON quebrado, campo obrigatório ausente) ou MS Fila indisponível → exceção → reentrega → após 5 tentativas vai para a DLQ → `EventoRejeitadoFunction` grava em `eventos_rejeitados` e loga evento de telemetria `EventoRejeitado`.

## 10. Pacotes Java

| Repo | Pacote raiz |
|---|---|
| ms-fila-sql | `br.com.openprontuario.fila` |
| ms-prontuario-mongo | `br.com.openprontuario.prontuario` |
| fn-visao-agregada | `br.com.openprontuario.visao` |

Subpacotes de camada (iguais nos três): `domain`, `application`, `infrastructure`, `api`, `bootstrap`. Vertical slice: `application.<feature>.<casodeuso>` (ex.: `application.fila.avisarchegada.AvisarChegadaUseCase`) e `application.<feature>.ports` para as portas.

## 11. Teste de contrato (obrigatório em cada serviço)

Cada repo copia o seu contrato para dentro do próprio repositório (`contract/<arquivo>.yaml`) e tem um teste automatizado que:
1. lê o contrato e extrai o conjunto `{MÉTODO caminho}` de `paths`;
2. obtém o conjunto equivalente do que está implementado (springdoc `/v3/api-docs` no Java; documento do `@nestjs/swagger` no BFF; para a Function, a lista de `@FunctionName`/`route` anotados);
3. normaliza os parâmetros de caminho para `{}` (ex.: `/fila/{id}` e `/fila/{unidadeId}` viram `/fila/{}`), porque o OpenAPI proíbe dois caminhos idênticos com nomes de variável diferentes — por isso `GET /fila/{id}` (id = unidadeId) e `DELETE /fila/{id}` (id = registroId) estão no mesmo *path item* do contrato;
4. falha se houver diferença em qualquer direção (rota faltando ou rota não documentada).

Rotas técnicas ignoradas na comparação: `/actuator/**`, `/v3/api-docs/**`, `/swagger-ui/**`, `/api/docs/**`.
