#!/usr/bin/env node
// Smoke test ponta a ponta contra o BFF (docker compose local ou nuvem).
// Uso: node scripts/e2e-smoke.mjs [BASE_URL]   (padrão: http://localhost:3000/api)
// Em nuvem, via API Gateway: APIM_KEY=<subscription key> node scripts/e2e-smoke.mjs https://<apim>/api
// Requer AUTH_MODE=dev no BFF. Sem dependências: Node 20+.

const BASE = (process.argv[2] ?? process.env.BFF_URL ?? 'http://localhost:3000/api').replace(/\/$/, '');
const UNIDADE = 'upa-01';
const ESPERA_FUNCTION_MS = 90_000;
const APIM_KEY = process.env.APIM_KEY;

let passos = 0;
const ok = (msg) => console.log(`  ✔ ${++passos}. ${msg}`);
const falhar = (msg, extra) => {
  console.error(`  ✘ ${msg}`);
  if (extra !== undefined) console.error(JSON.stringify(extra, null, 2));
  process.exit(1);
};
const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

async function chamar(metodo, caminho, { token, corpo, status } = {}) {
  const resp = await fetch(BASE + caminho, {
    method: metodo,
    headers: {
      ...(APIM_KEY ? { 'Ocp-Apim-Subscription-Key': APIM_KEY } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(corpo ? { 'Content-Type': 'application/json' } : {}),
    },
    body: corpo ? JSON.stringify(corpo) : undefined,
  });
  const texto = await resp.text();
  const json = texto ? JSON.parse(texto) : null;
  if (status !== undefined && resp.status !== status) {
    falhar(`${metodo} ${caminho} → esperado ${status}, recebido ${resp.status}`, json);
  }
  return { status: resp.status, json, correlationId: resp.headers.get('x-correlation-id') };
}

async function token(usuarioId) {
  const { json } = await chamar('POST', '/auth/dev-token', { corpo: { usuarioId }, status: 200 });
  return json.accessToken;
}

// Espera a visão agregada (Function) refletir o estado operacional (MS Fila) depois de `desde`.
async function esperarVisaoConsistente(tokenAtendente, desde, descricao) {
  const limite = Date.now() + ESPERA_FUNCTION_MS;
  let ultimo;
  while (Date.now() < limite) {
    const { json } = await chamar('GET', `/aggregated-data?unidadeId=${UNIDADE}`, { token: tokenAtendente, status: 200 });
    ultimo = json;
    const v = json.visaoAgregada;
    const fila = json.fila ?? [];
    const aCaminho = fila.filter((r) => r.status === 'A_CAMINHO').length;
    const presentes = fila.filter((r) => r.status === 'AGUARDANDO').length;
    if (v?.atualizadoEm && new Date(v.atualizadoEm) >= desde && v.totalACaminho === aCaminho && v.totalPresente === presentes) {
      ok(`${descricao}: Function recalculou a visão (a caminho=${aCaminho}, presentes=${presentes}, nível=${v.nivelCongestionamento})`);
      return json;
    }
    await esperar(2000);
  }
  falhar(`${descricao}: visão agregada não ficou consistente em ${ESPERA_FUNCTION_MS / 1000}s`, ultimo);
}

console.log(`E2E smoke — ${BASE}\n`);

await chamar('GET', '/health', { status: 200 });
ok('BFF saudável');

const tPaciente = await token('pac-101');
const tAtendente = await token('usr-atendente-07');
const tProfissional = await token('usr-prof-03');
const tGestor = await token('usr-gestor-01');
ok('tokens dev emitidos para paciente, atendente, profissional e gestor');

// Limpeza de execuções anteriores (o teste precisa ser repetível).
{
  const { json: fila } = await chamar('GET', `/fila/${UNIDADE}`, { token: tAtendente, status: 200 });
  for (const r of fila.filter((r) => r.pacienteId === 'pac-101')) {
    const motivo = r.status === 'EM_ATENDIMENTO' ? 'ATENDIDO' : 'DESISTENCIA';
    await chamar('DELETE', `/fila/${r.id}?motivo=${motivo}`, { token: tAtendente, status: 204 });
  }
  const { json: consentimentos } = await chamar('GET', '/consentimentos?apenasAtivos=true', { token: tPaciente, status: 200 });
  for (const c of consentimentos.filter((c) => c.unidadeId === UNIDADE)) {
    await chamar('DELETE', `/consentimentos/${c.id}`, { token: tPaciente, status: 204 });
  }
  ok('estado anterior do paciente pac-101 limpo');
}

const proximas = await chamar('GET', '/unidades/proximas?latitude=-25.4284&longitude=-49.2733&raioKm=20', { token: tPaciente, status: 200 });
if (!proximas.json.some((u) => u.id === UNIDADE)) falhar('upa-01 não aparece nas unidades próximas', proximas.json);
ok(`unidades próximas (MS Fila + Function): ${proximas.json.map((u) => `${u.id} ${u.distanciaKm?.toFixed?.(1)} km`).join(', ')}`);

let t0 = new Date();
const aviso = await chamar('POST', `/fila/${UNIDADE}/aviso-chegada`, {
  token: tPaciente,
  corpo: { sintomas: ['dor no peito', 'falta de ar'], tempoEstimadoChegadaMin: 15, autorizarProntuario: false },
  status: 201,
});
const registroId = aviso.json.id;
if (aviso.json.status !== 'A_CAMINHO' || aviso.json.prioridade !== 'MUITO_URGENTE') falhar('aviso de chegada com status/prioridade inesperados', aviso.json);
ok(`paciente avisou chegada (A_CAMINHO, prioridade preliminar MUITO_URGENTE), correlationId=${aviso.correlationId}`);
await esperarVisaoConsistente(tAtendente, t0, 'evento PACIENTE_A_CAMINHO');

t0 = new Date();
const chegada = await chamar('POST', `/fila/${registroId}/confirmar-chegada`, { token: tAtendente, status: 200 });
if (chegada.json.status !== 'AGUARDANDO') falhar('confirmar chegada não levou a AGUARDANDO', chegada.json);
ok('atendente confirmou a chegada (AGUARDANDO)');
await esperarVisaoConsistente(tAtendente, t0, 'evento PACIENTE_CHEGOU');

const semConsentimento = await chamar('GET', `/prontuarios/pac-101?unidadeId=${UNIDADE}`, { token: tProfissional, status: 403 });
if (semConsentimento.json?.codigo !== 'CONSENTIMENTO_AUSENTE') falhar('403 sem o código CONSENTIMENTO_AUSENTE', semConsentimento.json);
ok('profissional sem consentimento recebe 403 CONSENTIMENTO_AUSENTE');

const consentimento = await chamar('POST', '/consentimentos', { token: tPaciente, corpo: { unidadeId: UNIDADE, validadeDias: 3 }, status: 201 });
ok(`paciente concedeu consentimento (expira em ${consentimento.json.expiraEm})`);

const prontuario = await chamar('GET', `/prontuarios/pac-101?unidadeId=${UNIDADE}`, { token: tProfissional, status: 200 });
ok(`profissional leu o prontuário ${prontuario.json.id} (alergias: ${prontuario.json.alergias.join(', ')})`);

const auditoria = await chamar('GET', `/auditoria/prontuarios/${prontuario.json.id}`, { token: tPaciente, status: 200 });
if (!auditoria.json.some((l) => l.usuarioId === 'usr-prof-03' && l.consentimentoId === consentimento.json.id)) falhar('acesso não auditado', auditoria.json);
ok('acesso registrado na auditoria com o consentimentoId');

const agregado = await chamar('GET', `/aggregated-data?unidadeId=${UNIDADE}&pacienteId=pac-101`, { token: tProfissional, status: 200 });
const itemFila = agregado.json.fila?.find((r) => r.id === registroId);
if (!itemFila?.prontuarioAutorizado || !agregado.json.prontuario || !agregado.json.visaoAgregada || agregado.json.meta.degraded) {
  falhar('aggregated-data incompleto', agregado.json);
}
ok(`/aggregated-data uniu ${agregado.json.meta.fontes.map((f) => `${f.nome}(${f.duracaoMs}ms)`).join(' + ')}`);

t0 = new Date();
await chamar('POST', `/fila/${registroId}/iniciar-atendimento`, { token: tProfissional, status: 200 });
await chamar('POST', `/fila/${registroId}/confirmar-chegada`, { token: tAtendente, status: 409 });
ok('atendimento iniciado; transição inválida devolve 409');
await chamar('DELETE', `/fila/${registroId}?motivo=ATENDIDO`, { token: tProfissional, status: 204 });
ok('registro encerrado (FINALIZADO, motivo ATENDIDO)');
await esperarVisaoConsistente(tAtendente, t0, 'eventos ATENDIMENTO_INICIADO e PACIENTE_REMOVIDO');

await chamar('DELETE', `/consentimentos/${consentimento.json.id}`, { token: tPaciente, status: 204 });
await chamar('GET', `/prontuarios/pac-101?unidadeId=${UNIDADE}`, { token: tProfissional, status: 403 });
ok('revogação tem efeito imediato (403 na leitura seguinte)');

const nova = await chamar('POST', '/unidades', { token: tGestor, corpo: { nome: 'UPA Teste E2E', tipo: 'UPA', latitude: -25.5, longitude: -49.3 }, status: 201 });
await chamar('PUT', `/unidades/${nova.json.id}`, { token: tGestor, corpo: { nome: 'UPA Teste E2E (editada)', tipo: 'UPA', latitude: -25.5, longitude: -49.3 }, status: 200 });
await chamar('GET', `/unidades/${nova.json.id}`, { token: tGestor, status: 200 });
await chamar('DELETE', `/unidades/${nova.json.id}`, { token: tGestor, status: 204 });
ok('CRUD de unidade pelo gestor (criar, editar, ler, remover)');

await chamar('POST', `/fila/${UNIDADE}/aviso-chegada`, { token: tAtendente, corpo: { sintomas: ['febre'] }, status: 403 });
ok('perfil errado é barrado pelo BFF (403)');

console.log(`\nE2E OK — ${passos} verificações.`);
