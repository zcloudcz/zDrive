# Release → Azure test deploy + headless backup CLI

Zadání pro Sonnet agenty. Cíl: dostat zDrive (Phase 0–4, **bez AI**) do
nasaditelného stavu na **Azure Container Apps** (test env) a přidat
**headless API použití** — Linux server zálohuje data přes API bez Flutter
klienta.

## Rozhodnutí (fixní, neměnit bez domluvy)

- **Deploy target: Azure Container Apps** (ne AKS). Scale-to-zero, spravovaný
  ingress. Existující Terraform AKS modul + Helm charty se pro tento účel
  **nepoužijí** (nechat v repu, jen se nevolají).
- **PaaS backing services**: Postgres Flexible Server (Burstable B1ms),
  Azure Cache for Redis (Basic), Azure Blob Storage (real, ne Azurite),
  Azure Service Bus (Basic). Seq → nahradit Container App nebo vynechat,
  logy do Container Apps Log Analytics.
- **Schema**: služby volají `EnsureCreatedAsync()` na startu — fresh test DB
  si schema vytvoří sama. Žádný EF migration job zatím netřeba.
- **Headless auth**: dedikovaný service user (email+heslo) + `login`/`refresh`
  JWT. **Nestavět** API-key infrastrukturu (YAGNI pro test).
- **AI (Phase 5) přeskočeno.** PhotoService běží v základu (Phase 4), AI
  workery se nenasazují ani neřeší.

## Aktuální stav (ověřeno v kódu)

- Dockerfily jen `ApiGateway` + `AuthService`. Chybí: File, Storage, Sync,
  Photo, Notification.
- `docker-compose.yml` = jen infra (postgres, redis, azurite, seq, rabbitmq),
  **ne** služby samotné.
- `deploy-staging.yml` = samé TODO stuby.
- Terraform provisuje AKS (nepoužít).
- JWT: `Jwt:RsaPrivateKeyPem`/`RsaPublicKeyPem` z configu; mimo Development
  je chybějící klíč hard-fail. Validující služby potřebují public key.
- YARP gateway Clusters mají hardcoded `http://localhost:510X`.
- Upload je klientem orchestrovaný:
  `login` → `POST storage/upload/init` → `PUT storage/upload/{sid}/chunk/{i}`
  → `POST storage/upload/{sid}/complete` → `POST file/files` (metadata).
  Chunking (~4 MB) dělá klient.

## DAG agentů

```
Agent 1 (Release-ready services) ─┐
                                   ├─→ Agent 3 (CI/CD deploy)
Agent 2 (Azure infra) ────────────┘
Agent 4 (Linux backup CLI) ── nezávislý (testuje proti local stacku)
Agent 5 (PhotoService testy) ── nezávislý
```

- Agent 1, 2, 4, 5 startují paralelně.
- Agent 3 až po merge 1 + 2 (potřebuje Dockerfily i názvy Azure resourců).

---

## Agent 1 — Release-ready services

**Cíl**: každá ze 7 služeb je containerizovaná a konfigurovatelná z prostředí
(env / Key Vault), bez dev-only fallbacků v produkčním běhu.

**Úkoly**
1. **Dockerfily** pro chybějících 5 služeb (File, Storage, Sync, Photo,
   Notification). Kopírovat vzor z `src/services/AuthService/Dockerfile`.
   Multi-stage (sdk build → aspnet runtime), non-root user, expose port,
   `HEALTHCHECK` na `/health/live`.
2. **`docker-compose.prod.yml`** — rozšíří základní compose o všech 7 služeb
   (buildnutých z Dockerfilů) + infra. Slouží k lokálnímu ověření celého
   stacku před Azure deployem. Env přes `.env` (nezakomitovat).
3. **JWT klíče z configu**: ověř že všechny validující služby čtou
   `Jwt:RsaPublicKeyPem` z konfigurace (ne jen dev file provider). AuthService
   navíc private key. Klíče se budou injektovat env proměnnou / Key Vault ref
   (viz Agent 2). Žádné dev fallbacky když `ASPNETCORE_ENVIRONMENT != Development`.
4. **Gateway routing z prostředí**: YARP `Clusters:*:Address` přepnout z
   hardcoded localhost na hodnoty z env/config
   (`ReverseProxy:Clusters:{svc}:Destinations:...:Address`). V Azure poletí
   interní FQDN Container Apps.
5. **Connection strings z env**: DB / Redis / Blob / Service Bus výhradně přes
   env proměnné dle `CLAUDE.md` (`DATABASE_CONNECTION_STRING`,
   `REDIS_CONNECTION_STRING`, `AZURE_STORAGE_CONNECTION_STRING`,
   `SERVICE_BUS_CONNECTION_STRING`). Ověř že žádná služba nemá natvrdo
   Azurite `UseDevelopmentStorage=true` mimo Development.
6. **Health checks**: potvrď `/health/live` + `/health/ready` na všech
   službách (Container Apps probes je budou volat).
7. **CORS**: gateway povolí origin test klienta (konfigurovatelně přes env).

**Akceptace**
- `docker compose -f docker-compose.yml -f docker-compose.prod.yml up` nastartuje
  všech 7 služeb + infra, `/health/ready` na gateway vrátí 200.
- E2E lokálně: `register → login → upload souboru přes gateway → download`
  vrátí bit-identická data (skript nebo doložený curl log).
- Žádná služba nespadne kvůli chybějícímu JWT klíči když se dodá přes env.

**Ověření**: `docker compose ... up`, health endpoints, upload/download smoke test.

---

## Agent 2 — Azure infra (Terraform → Container Apps)

**Cíl**: Terraform stack který naprovisuje test prostředí na Container Apps
+ PaaS backing services, jedním `terraform apply`.

**Úkoly**
1. Nový Terraform config (vedle stávajícího, AKS nechat být) nebo
   `environments/test.tfvars` + Container Apps moduly. Provisovat:
   - Resource Group (test).
   - **Azure Container Registry** (Basic).
   - **Container Apps Environment** + Log Analytics workspace.
   - 7× **Container App** (jedna na službu). Gateway = external ingress
     (public FQDN + TLS zdarma), ostatní = internal ingress.
   - **Postgres Flexible Server** (B1ms, jedna instance; služby sdílí server,
     každá svoje schema/db). Firewall allow Azure services.
   - **Azure Cache for Redis** (Basic C0).
   - **Storage Account** + Blob container.
   - **Service Bus** namespace (Basic) + potřebné queues/topics
     (zjistit z kódu jaké názvy služby očekávají).
   - **Key Vault** — JWT RSA keypair (private+public), connection stringy.
2. **Outputs**: gateway public FQDN, ACR login server, názvy Container Apps,
   Key Vault URI — vše co Agent 3 potřebuje pro deploy pipeline.
3. **Container App config**: env proměnné mapované na Key Vault secret refs
   (JWT, connection strings). Interní service-to-service komunikace přes
   internal FQDN (`http://{app}.internal.{env-domain}` / dle Container Apps
   DNS). Min replicas 0 (scale-to-zero) kde to dává smysl, gateway min 1.
4. JWT keypair vygenerovat mimo Terraform state (nebo přes
   `azurerm_key_vault_secret` s hodnotou dodanou jako var, ne v repu).
   **Klíče nikdy do repa ani do tfvars v gitu.**

**Akceptace**
- `terraform plan` s `test.tfvars` projde bez chyb, ukáže očekávané resources.
- Dokumentované outputs (README v `infra/terraform/`) — jak je Agent 3 čte.
- Žádné secrets v repu (gitleaks čistý).

**Ověření**: `terraform validate` + `terraform plan`. Reálný `apply` dělá
člověk (potřebuje Azure subscription / credentials).

---

## Agent 3 — CI/CD deploy pipeline

**Předpoklad**: Agent 1 (Dockerfily) + Agent 2 (infra + outputs) mergnuté.

**Cíl**: `deploy-staging.yml` (nebo nový `deploy-test.yml`) buildne, pushne a
nasadí všech 7 služeb na Container Apps.

**Úkoly**
1. Nahradit TODO stuby v deploy workflow reálnými kroky:
   - Azure login (OIDC / service principal ze secrets).
   - `az acr build` nebo docker build+push všech 7 images do ACR,
     tag = `${{ github.sha }}`.
   - `az containerapp update` (nebo `up`) pro každou službu na nový image tag.
2. Trigger: `workflow_dispatch` (manuální pro test) + volitelně push na `main`.
   Pro test radši manuální, ať se nedeployuje omylem.
3. Secrets: dokumentovat požadované GitHub secrets (ACR, Azure creds, RG).
4. Smoke test krok po deployi: curl `/health/ready` na gateway public FQDN,
   fail pipeline když != 200.

**Akceptace**
- Workflow soubor validní (`actionlint` / GitHub parser).
- Dokumentované secrets a manuální spuštění.
- Dry-run / doložený běh proti test RG (pokud jsou credentials k dispozici),
  jinak popsat co člověk musí dodat.

**Ověření**: workflow lint; reálný běh po dodání Azure secrets člověkem.

---

## Agent 4 — Linux headless backup CLI

**Cíl**: samostatný nástroj běžící na Linux serveru který nahraje soubory/
adresáře do zDrive přes veřejné API, bez Flutter klienta. Pro zálohy.

**Rozhodnutí**
- **Jazyk**: .NET 8 console app (`src/tools/ZDrive.BackupCli/`) — sdílí
  existující DTO/kontrakty z `src/shared`, tým už umí .NET. (Pokud agent
  usoudí že standalone Python/Go skript je výrazně jednodušší a bez potřeby
  shared kontraktů, smí navrhnout — ale default .NET.)
- Auth: dedikovaný user, credentials z env / config souboru
  (`ZDRIVE_API_URL`, `ZDRIVE_USER`, `ZDRIVE_PASSWORD`). Token refresh
  automaticky. **Heslo nikdy do logu ani do repa.**

**Úkoly**
1. Replikovat upload orchestraci kterou dnes dělá Flutter klient:
   `login` → chunking souboru (~4 MB, stejná logika jako klient/StorageService
   očekává) → `upload/init` → `PUT chunk/{i}` → `upload/complete` → zápis
   metadat `POST file/files`. Ověřit v kódu klienta
   (`src/client/zdrive_app/lib/features/files`) přesný tvar payloadů a pořadí.
2. **Backup režim**: rekurzivně projít lokální adresář, zrcadlit strukturu
   složek do zDrive (vytvořit chybějící složky přes FileService), nahrát
   soubory. Idempotence: přeskočit soubory které už existují se stejným
   obsahem (dedup se dělá na úrovni chunků server-side — využít, nebo
   porovnat hash/velikost před uploadem, ať se nenahrává zbytečně).
3. **Resumability (základní)**: když upload spadne, další běh dokončí zbytek.
   Stačí re-scan + skip existujících (žádný složitý state store — YAGNI).
4. Progress výstup na stdout, chyby na stderr, nenulový exit code při selhání
   (aby šlo pouštět z cronu).
5. README: instalace na Linux, env proměnné, příklad
   `zdrive-backup /data/photos --dest /backup/photos`, cron příklad.

**Akceptace**
- Proti lokálnímu stacku (Agent 1 compose): nahraje adresář s vnořenými
  složkami, po `download` sedí obsah bit-po-bitu.
- Druhý běh nenahrává už nahrané soubory (idempotence ověřená v testu/logu).
- Přerušený běh (kill uprostřed) → další běh dokončí, výsledek kompletní.
- Špatné heslo → jasná chyba + nenulový exit, žádné heslo v logu.

**Ověření**: integrační test proti compose stacku (upload → download → diff),
idempotence test (dvojí běh), interrupt test.

---

## Agent 5 — PhotoService integrační testy

**Cíl**: PhotoService (Phase 4, základní fotky — **bez AI**) dostat na
stejnou úroveň test coverage jako ostatní služby. Dnes jako jediná nemá
`.Tests` projekt → porušuje repo pravidlo "no phase exits without green
integration tests".

**Kontext**
- PhotoService závisí jen na **Postgres** (`PhotoDbContext`,
  `EnsureCreatedAsync` na startu). Žádný blob/service bus v základních ops.
- Vzor testů převzít z `src/services/FileService.Tests/` — `WebApplicationFactory`,
  `Testcontainers.PostgreSql`, xunit, FluentAssertions (viz jejich `.csproj`).

**Úkoly**
1. Založit `src/services/PhotoService.Tests/` dle vzoru ostatních
   (`PhotoServiceFactory` s Testcontainers Postgres, `EnsureCreatedAsync`).
2. Přidat projekt do solution (`.sln`) a do `backend-ci.yml` filtru pokud
   je potřeba (ověřit že CI test discovery ho vezme).
3. Integrační testy — každý endpoint aspoň happy-path + jedna error-path:
   - **Photos**: `POST ingest` → foto vznikne → `GET timeline` ho vrátí;
     `GET {id}`; `GET search`; `POST {id}/tags` (manuální tag, ne AI).
   - **Albums**: `POST` album → `GET`; `POST {id}/photos` přidá foto →
     `GET {id}/photos`; `DELETE {id}/photos/{photoId}`; `PUT {id}` rename;
     `DELETE {id}`.
   - **Memories**: `GET`; `POST {id}/dismiss`.
   - Error-path příklady: `GET {id}` neexistující → 404; ingest s nevalidním
     payloadem → 400; album operace na cizím/neexistujícím ID → 404/403.
4. Naming dle repo konvence: `{MethodOrFeature}_{Scenario}_{ExpectedResult}`.
5. **AI mimo scope**: netestovat auto-tagging, faces, clustering, memory
   generation z AI. Jen manuální/základní cesty co dnes reálně běží.

**Akceptace**
- `dotnet test src/services/PhotoService.Tests` zelené lokálně.
- Každý endpoint z Albums/Memories/Photos controllerů má ≥1 happy + ≥1 error test.
- CI (`backend-ci.yml`) testy spustí a projde.
- Žádná regrese v testech ostatních služeb.

**Ověření**: `dotnet test` + běh v CI.

---

## Globální pravidla

- Každý agent ve vlastním git worktree, merge přes PR, CI musí projít.
- Code review: `hydra` agent (deleguje na Codex) — bez schválení se nemerguje.
- Secrets nikdy do repa. gitleaks běží na každém push.
- Testy: integrační proti reálné infře (Testcontainers vzor už v repu).
- Komunikace/commenty CZ, kód/identifikátory/komentáře EN (dle repo konvence).
