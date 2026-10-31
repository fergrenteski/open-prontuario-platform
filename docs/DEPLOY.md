# Deploy em nuvem (Azure + MongoDB Atlas + Docker Hub)

Tudo em nuvem é ligado, testado e desligado pelo `scripts/azure.sh`:

```bash
./scripts/azure.sh subir      # cria ou atualiza tudo (~20 min na 1ª vez, ~5 min depois)
```

```bash
./scripts/azure.sh status     # está no ar? quais são as URLs?
```

```bash
./scripts/azure.sh acordar    # tira os serviços da partida a frio: rode antes de apresentar
```

```bash
./scripts/azure.sh testar     # smoke test E2E (19 verificações) contra o API Gateway
```

```bash
./scripts/azure.sh desligar   # apaga tudo da Azure: custo zero
```

## Ligar e desligar (conta Azure for Students)

| Situação | O que fazer | Custo |
|---|---|---|
| Vai apresentar ou o professor vai corrigir | deixe ligado | ~US$ 0,35/dia (só o Service Bus Standard cobra parado) |
| Semanas sem usar | `./scripts/azure.sh desligar` | zero |
| Precisa de novo | `./scripts/azure.sh subir` | ~20 min para ficar no ar |

Tudo escala a zero, então o primeiro acesso depois de um tempo parado leva até ~1 min (a tela mostra "Buscando…"). Antes de apresentar ou gravar o vídeo, rode `acordar`.

Parado, quase nada cobra: Container Apps e Functions (Flex Consumption) escalam a zero, o API Management Consumption cobra por chamada, o Azure SQL usa a oferta gratuita com auto-pause e o Static Web Apps é Free. Por isso não existe "pausar": o único custo fixo é o Service Bus, que não pausa.

Ao desligar e subir de novo:
- as URLs do API Gateway e da Function **continuam iguais** (o nome vem do resource group);
- as URLs do frontend (Static Web Apps) e dos Container Apps **mudam**: rode `status` e atualize os links;
- o banco do MS Fila volta ao seed inicial; o MongoDB Atlas não é apagado.

## Configuração (uma vez)

### 1. MongoDB Atlas (M0, gratuito)

1. Crie um cluster **M0** (São Paulo).
2. *Database Access*: crie um usuário com `readWriteAnyDatabase`.
3. *Network Access*: libere `0.0.0.0/0`. Container Apps e Functions em consumo não têm IP fixo; a proteção é usuário, senha e TLS (risco registrado no arc42, seção 11).
4. Copie a connection string `mongodb+srv://...`.

Com o Atlas CLI (`brew install mongodb-atlas-cli` e `atlas auth login`) os mesmos passos são `atlas clusters create`, `atlas dbusers create` e `atlas accessLists create`.

### 2. Imagens no Docker Hub

O Docker Hub só aceita um nível de namespace, então as imagens são `<usuario>/pjbl-<servico>:<tag>`.

```bash
docker login
```

```bash
./scripts/docker-publish.sh <usuario-dockerhub> v1
```

### 3. `.env.azure`

```bash
cp .env.azure.example .env.azure
```

Preencha `DOCKERHUB_USER`, `MONGODB_URI` e `APIM_EMAIL`. As senhas e chaves internas são geradas na primeira execução e guardadas no próprio `.env.azure`, que fica fora do git.

### 4. Subir

Pré-requisitos: Azure CLI, Docker (o deploy do frontend roda num container), JDK 17 e Node 20+.

```bash
az login
```

```bash
./scripts/azure.sh subir
```

Se a assinatura de estudante bloquear `brazilsouth`, use `LOCATION=eastus2` no `.env.azure`.

O `authMode` é `dev`, com as personas de demonstração (João, Maria, Carla, Dr. Paulo e Lúcia). Para usar o Microsoft Entra ID, siga o README do BFF.

## Entrega

1. Preencha a seção "Links da entrega" do `docs/arc42_open_prontuario_pjbl.md` com a saída de `status`.
2. Tire os prints de `docs/prints/CHECKLIST.md` e grave o vídeo seguindo `docs/video/ROTEIRO.md`.
3. Gere o PDF do arc42:

   ```bash
   cd docs && docker run --rm -v "$PWD":/data pandoc/latex:3.6 arc42_open_prontuario_pjbl.md -o arc42_open_prontuario_pjbl.pdf --toc -V geometry:margin=2cm
   ```

No fim do semestre, rode `./scripts/azure.sh desligar` e apague o cluster no Atlas.
