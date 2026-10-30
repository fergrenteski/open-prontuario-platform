# Roteiro do vídeo (≈ 10 min, YouTube "não listado")

Regras do PJBL: **todos os integrantes falam e se identificam**, e **tudo é mostrado em URLs de nuvem** (nada de `localhost`). Mantenha a barra de endereço visível em todas as cenas.

## Antes de gravar (checklist)

- [ ] Deploy feito (`docs/DEPLOY.md`) e links preenchidos no arc42.
- [ ] "Aquecer" os serviços (escala a zero): abra o Swagger do BFF, dos dois microserviços e chame `GET /api/health` uns 2 minutos antes.
- [ ] Estado limpo: `node scripts/e2e-smoke.mjs <URL do gateway>` uma vez (o script limpa o estado do paciente `pac-101` e valida tudo) — ou desfaça manualmente.
- [ ] Abas abertas: Frontend, Swagger BFF, Swagger MS Fila, Swagger MS Prontuário, portal Azure (Service Bus → tópico → subscription `agregador`, Function → Monitor/Log stream, API Management → Analytics), MongoDB Atlas (Browse Collections), Azure SQL (Query editor).
- [ ] Duas janelas do navegador lado a lado: **Paciente** (modo responsivo/celular) e **Atendente**.

## Cenas

| # | Tempo | Quem fala | O que mostrar | Fala-guia |
|---|---|---|---|---|
| 1 | 0:00–0:45 | **Luiz Fernando Grenteski** | Diagrama C4 Nível 2 (arc42) | "Sou o Luiz. Este é o Open Prontuário. O front fala só com o API Gateway, que encaminha ao BFF; o BFF consome o microserviço de Fila em Azure SQL, o de Prontuário em MongoDB Atlas e uma Azure Function." |
| 2 | 0:45–1:30 | **Bernardo Plottegher** | Portal Azure: resource group com APIM, Container Apps, Function, Service Bus, Azure SQL, Static Web Apps; Docker Hub com as 3 imagens | "Sou o Bernardo. Tudo foi provisionado com Bicep. As imagens estão no Docker Hub e os Container Apps puxam de lá." |
| 3 | 1:30–2:30 | **Luiz** | Frontend (URL do Static Web Apps) → login como **João (paciente)** → UPAs próximas com distância e nível de congestionamento | "Essa lista já é uma agregação: distância vem do MS Fila e os indicadores da Function, tudo pelo BFF." Mostrar no DevTools (aba Rede) que a chamada vai para a **URL do gateway**. |
| 4 | 2:30–3:45 | **Ana Paula Alves** | Paciente avisa chegada na UPA Boa Vista com "dor no peito, falta de ar", sem autorizar prontuário → prioridade preliminar MUITO_URGENTE | "Sou a Ana Paula. O MS Fila classificou a prioridade pelos sintomas, gravou no Azure SQL e publicou o evento PACIENTE_A_CAMINHO no Service Bus." Mostrar no portal o contador de mensagens do tópico / a execução da Function no Monitor e o documento em `visao.visao_agregada` no Atlas. |
| 5 | 3:45–5:00 | **Ana Paula** | Atendente (Carla) seleciona a UPA → fila com "a caminho" → **confirmar chegada** → **alterar prioridade** | "Cada ação é uma transição da máquina de estados e um evento. A fila se atualiza sozinha a cada 5 segundos." Mostrar a tabela `registros_fila` no Query editor do Azure SQL. Mostrar 409 tentando uma transição inválida (ex.: confirmar de novo). |
| 6 | 5:00–6:30 | **Artur Bertoni** | Profissional (Dr. Paulo) tenta abrir o prontuário → **403 consentimento ausente**; paciente concede consentimento; profissional abre → 200; paciente vê em "Meu prontuário" quem acessou | "Sou o Artur. O consentimento segue o Open Finance: por unidade, com prazo e revogável. Todo acesso grava auditoria antes de devolver o prontuário — se a auditoria falhar, nada é devolvido." Mostrar `prontuario.auditoria` no Atlas. Revogar e mostrar 403 de novo. |
| 7 | 6:30–7:30 | **Luiz** | Swagger do BFF → `GET /api/aggregated-data?unidadeId=upa-01&pacienteId=pac-101` executado no Swagger (com token) **e** a tela de Indicadores do gestor | "Este é o endpoint obrigatório: um único JSON com dados do SQL, do Mongo e da Function, com o tempo de cada fonte em `meta.fontes`." |
| 8 | 7:30–8:15 | **Bernardo** | Swagger do MS Fila e do MS Prontuário (CRUD), gestor criando/editando/removendo uma unidade no front; APIM → Analytics mostrando as chamadas | "CRUD completo nos dois microserviços, documentado com Swagger; o gateway centraliza a entrada e aplica rate limit." |
| 9 | 8:15–9:00 | **Bernardo** | Iniciar atendimento e encerrar → Function recalcula (Monitor); explicar DLQ (subscription `agregador` → Dead-letter) | "Se um evento falhar 5 vezes vai para a dead-letter queue e outra Function registra e alerta." |
| 10 | 9:00–10:00 | **Ana Paula** e **Artur** | GitHub: um dos repositórios com a árvore `domain/application/<feature>/<caso-de-uso>/infrastructure/api` e o CI verde (testes de arquitetura) | Ana: "Cada repositório segue Clean Architecture com Vertical Slice." Artur: "E testes de arquitetura quebram o build se alguém violar as camadas." Encerramento com os 4 nomes. |

## Dicas

- Grave em 1080p, zoom do navegador em 110–125%.
- Se algum serviço demorar (cold start), corte a espera na edição.
- Publique como **Não listado** e cole o link na seção "Links da entrega" do arc42.
