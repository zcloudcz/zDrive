# Témata pro firmy (B2B)

**Datum:** 2026-09-27
**Stav:** **zatím se neřeší** (rozhodnutí vlastníka 2026-09-27). Tento
dokument sbírá a rozvíjí témata, aby byla připravená, až se B2B otevře.
Přidávejte do něj průběžně. Zadání pro implementaci z něj vzniknou až po
rozhodnutí v kap. 2.

---

## 1. Výchozí stav v kódu

| Oblast | Stav | Kde |
|---|---|---|
| Tenant | entita `Tenant` (Id, Name, CreatedAt) | `AuthService.Domain/Entities/Tenant.cs` |
| Vznik tenanta | **každá registrace i každé první Entra přihlášení vytvoří nový tenant** a uživatel je jeho Owner | `RegisterCommandHandler.cs:48`, `EntraExchangeCommandHandler.cs:91` |
| Role | enum Viewer, Member, Admin, Owner; v JWT claim `role` a `tenant_id` | `JwtTokenGenerator.cs:33-34` |
| Vynucení rolí | **nikde**; `ClaimsHelper.GetRole` nemá volající | `shared/ZDrive.Shared/Auth/ClaimsHelper.cs:20` |
| Vlastnictví souborů | **per user** (`TenantId` + `UserId` ručně v každém handleru), ne per tenant | např. `ListChildrenQueryHandler` |
| EF global query filtry | nejsou (CLAUDE.md je slibuje) | — |
| Tenant/member API | není; `UsersController` má jen `me` | — |
| Audit log | není | — |
| Kvóty | per user (claim `quota_bytes`, fallback 50 GB); verze i koš se počítají | `StorageQuota.cs` |
| Přímé sdílení | uloží se, nic ho nečte (zadání 13) | `CreateShareCommandHandler.cs` |
| Branding | veřejná stránka sdílení je brandovaná zDrive, ne tenantem | `features/share_link` |
| MCP | přístup přes sdílené odkazy, bez tenantových politik | `ApiGateway/Mcp` |

Plán v `CLAUDE.md` (fáze 7) počítá s tenant management API, rolemi,
audit logem, hromadným provisioningem (CSV) a politikami sdílení.

---

## 2. Zásadní rozhodnutí (před jakoukoli implementací)

### 2.1 Datový model: čí jsou soubory?

| Varianta | Popis | Dopad |
|---|---|---|
| **A: osobní disky + správa účtů** | každý zaměstnanec má svůj disk, firma spravuje účty, kvóty a politiky | nejmenší zásah (soubory zůstanou per user); sdílení v týmu přes zadání 13 |
| **B: A + týmové složky** | navíc „Týmové disky" vlastněné tenantem (jako Google Shared Drives) s členstvím a rolemi | nový typ vlastníka uzlu (user/team), změna kvót, sync klient musí umět víc kořenů |
| **C: vše patří tenantovi** | soubory patří firmě, uživatel je jen autor | největší přepis FileService, nejhorší pro B2C |

*Doporučení:* A jako první krok, B jako cíl. Nejdřív udělat zadání 13,
protože oprávnění mimo vlastníka jsou pro B stejně potřeba.

### 2.2 Jak vzniká firma a jak se do ní dostane člověk

- Dnes 1 registrace = 1 tenant. Pro firmy je potřeba: založení firemního
  tenanta, pozvánka e-mailem (přes MailNotify), přijetí pozvánky existujícím
  účtem (přesun z osobního tenanta? co s jeho daty?), odchod z firmy.
- Otázka: může mít jeden člověk osobní i firemní prostor (jako OneDrive
  Personal + Business)? Pokud ano, přihlášení musí umět vybrat tenant a
  JWT nese jeden `tenant_id`.

### 2.3 Identita pro firmy

- **ZCLOUD External ID** (dnešní Entra) je identita *zákazníka ZCLOUD*.
- Firmy budou chtít **vlastní** identitu: jejich Entra ID (workforce),
  Google Workspace, případně SAML. To je multitenant app registrace nebo
  federace, ne External ID tenant ZCLOUD. Viz `entra-external-id.md`.
- Varianta, kterou nabízí External ID: federace OIDC IdP zákazníka do
  `zcloud_signin`. Ověřit limity a cenu (MAU se počítají).

### 2.4 Obchodní model

Cena za uživatele, nebo za TB? Sdílená kvóta tenanta, nebo per user?
Fakturace (vlastní, nebo přes ZCLOUD)? Ovlivňuje model kvót (kap. 3.6).

---

## 3. Katalog témat

Každé téma: *co to je*, *proč to firmy chtějí*, *co existuje*, *co je
potřeba*, *závislosti*. Priorita P1 znamená, že bez tématu nejde prodat
první firmě.

### 3.1 Členové a role (P1)
- **Co:** pozvat, odebrat, změnit roli (Owner, Admin, Member, Viewer).
  Owner nejde odebrat, dokud není jiný Owner.
- **Existuje:** enum a claim. **Chybí:** API, UI, vynucení (policy
  `RequireRole` v Api), přechod uživatele mezi tenanty.
- **Pozor:** role je v JWT, takže změna role se projeví až po refreshi
  (max. 15 min). Pro odebrání člena je potřeba revokovat refresh tokeny.
- **Závisí na:** 2.1, 2.2, MailNotify (pozvánky).

### 3.2 Admin konzole (P1)
- **Co:** přehled členů, využití úložiště, kvóty, pozvánky, politiky.
- **Kde:** nová sekce ve Flutter aplikaci (web first) pro role Admin/Owner.
- **Závisí na:** 3.1.

### 3.3 Audit log (P1)
- **Co:** kdo, co, kdy, odkud. Přihlášení, změny členů a rolí, sdílení
  (vytvoření a zrušení odkazu), smazání a obnova, stažení přes veřejný
  odkaz, přístup přes MCP, změny politik.
- **Existuje:** `file_changes` (ADR 0001) pokrývá mutace souborů, ale ne
  čtení, sdílení ani auth události.
- **Potřeba:** append-only tabulka ve vlastním schématu, zápis ve stejné
  transakci (vzor `FileChangeInterceptor`), filtrovatelné API + export
  CSV, retence (konfigurovatelná, výchozí 1 rok?).
- **Otázka:** logovat stažení (čtení)? U firem ano, je to drahé na objem.

### 3.4 Politiky sdílení (P1)
- **Co:** zakázat veřejné odkazy, vynutit expiraci nebo heslo, zakázat
  zápis přes odkaz, povolit sdílení jen na vybrané domény, zakázat MCP
  přístup nebo ho omezit na čtení.
- **Existuje:** odkaz umí heslo, expiraci a allow-delete, ale nejsou
  tenantové politiky.
- **Potřeba:** `TenantPolicy` + kontrola v `CreateShare`, `PublicShareAccess`
  a MCP gateway.

### 3.5 Firemní SSO a provisioning (P2)
- **SSO:** Entra ID zákazníka, Google Workspace, SAML (viz 2.3).
- **Provisioning:** SCIM 2.0 (automatické zakládání a rušení účtů z
  firemního adresáře); hromadný import CSV jako levnější první krok (je
  v plánu fáze 7).
- **Vynucení 2FA** pro všechny členy tenanta (navazuje na zadání 01).

### 3.6 Kvóty a licence (P1)
- **Co:** kvóta tenanta (sdílená), kvóta per user, počet licencí (seats).
  Upozornění při 80 a 100 %.
- **Existuje:** per-user kvóta z claimu. **Pozor:** koš a všechny verze se
  počítají, u firem to bude zdroj stížností. Rozhodnout, co se účtuje.
- **Závisí na:** 2.4.

### 3.7 Offboarding zaměstnance (P2)
- **Co:** při odchodu převést jeho soubory a sdílení na jiného člena
  (typicky vedoucího), zablokovat přihlášení, zrušit relace, odhlásit
  zařízení.
- **Potřeba:** operace „transfer ownership" nad stromem uzlů (s ohledem na
  kvóty a verze), revokace refresh tokenů, device registry (SyncService má
  registraci zařízení).

### 3.8 Správa zařízení (P3)
- **Co:** seznam zařízení člena, vzdálené odhlášení, u mobilů smazání
  lokální cache.
- **Existuje:** registrace zařízení v SyncService (`device_registration_service.dart`).

### 3.9 Retence, legal hold, GDPR (P2)
- **Co:** minimální retence smazaných souborů pro firmu (koš > 30 dní),
  legal hold (nic nejde nenávratně smazat), export všech dat tenanta,
  smazání tenanta.
- **Existuje:** koš 30 dní, retence verzí (zadání 12). GDPR export je až ve
  fázi 8.
- **Pozor:** GC blobů zatím neexistuje, takže „smazáno" dnes neznamená
  fyzicky smazáno. Pro smlouvy se zákazníky to musí být pravdivě popsané.

### 3.10 Smluvní a compliance minimum (P1, mimo kód)
- Zpracovatelská smlouva (DPA, GDPR čl. 28), seznam subdodavatelů
  (Microsoft Azure, poskytovatel SMTP pro MailNotify), umístění dat
  (Azure West Europe), popis zabezpečení (šifrování at rest, TLS, zálohy,
  RPO/RTO). Viz poznámka o CLOUD Act v `competitive-analysis.md` 6.3.

### 3.11 Branding tenanta (P3)
- Logo a název firmy na veřejné stránce sdílení a v e-mailech. Veřejná
  stránka je už brandovaná (#50), takže stačí per-tenant hodnoty.

### 3.12 AI a MCP pro firmy (P2, diferenciátor)
- MCP přístup je unikátní vlastnost zDrive (viz analýza konkurence). Firmy
  budou chtít: MCP jen pro vybrané složky, jen čtení, audit každého
  přístupu agenta (3.3) a možnost MCP úplně vypnout (3.4).
- Možná nabídka: „bezpečné napojení firemních dokumentů na AI agenty"
  jako prodejní argument pro SMB.

### 3.13 Partnerský model (P3, nápad)
- Účetní kanceláře, IT správci a MSP spravují více firem. Partner vidí své
  klienty, zakládá tenanty a má omezený přístup. Zajímavá niche na českém
  trhu, kde konkurence (Google, Microsoft) takový model pro malé partnery
  nemá jednoduchý.

---

## 4. Návrh pořadí (až se B2B otevře)

```
0. Rozhodnutí 2.1–2.4 + zadání 13 (přímé sdílení) hotové
1. Tenant model: založení firmy, pozvánky (MailNotify), členové a role + vynucení (3.1)
2. Audit log (3.3) + politiky sdílení (3.4) + kvóty tenanta (3.6)
3. Admin konzole (3.2)
4. Offboarding (3.7), vynucení 2FA, CSV import
5. Firemní SSO / SCIM (3.5), retence a legal hold (3.9)
6. Týmové složky (varianta B), branding (3.11), partnerský model (3.13)
```

## 5. Otázky pro vlastníka

1. Model souborů A, B nebo C (2.1)?
2. Osobní a firemní prostor pro jednoho člověka zároveň (2.2)?
3. Cena za uživatele, nebo za kapacitu (2.4)?
4. Kdo je první cílový zákazník (typ firmy a velikost)? Určí to prioritu
   mezi 3.5 (SSO) a 3.13 (partneři).
