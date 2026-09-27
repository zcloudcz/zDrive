# Zadání 03: Obnova hesla e-mailem (přes MailNotify)

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers, migrace přes
> `--startup-project src/services/Api`, komunikace česky, kód anglicky.
> Pokud je něco v zadání nejasné nebo neodpovídá kódu, zastav se a zeptej se.

## Cíl

„Zapomněl jsem heslo" → e-mail s odkazem → nastavení nového hesla. E-maily
odesílá **MailNotify**, centrální notifikační služba ZCLOUD
(repo `zcloudcz/MailNotify`, rozhodnuto vlastníkem 2026-09-27). zDrive
nebude mít vlastní SMTP.

## MailNotify: co potřebuješ vědět

- `POST {BaseUrl}/api/email`, tělo `SendEmailRequest` (`To[]`, `Subject`,
  `Html` | `Text` | `TemplateId` + `Model`, volitelně `From`, `ReplyTo`).
  Kontrakt je v `src/MailNotify.Shared/SendContracts.cs` repa MailNotify.
  Odpověď 200 bez těla, chyba validace 400. Odesílá synchronně přes SMTP
  profil.
- **Auth:** Entra **app token** (client credentials) z tenantu
  `zcloudcz.ciamlogin.com`. Volající app registrace musí mít app roli
  `Notify.Send`. Scope je `api://<mailnotify-api-client-id>/.default`.
  Hotový klient `clients/MailNotifyClient.cs` z repa MailNotify stačí
  zkopírovat. Je to jeden soubor s `Azure.Identity` `ClientSecretCredential`
  a komentář nahoře popisuje registraci.
- **Šablony:** `TemplateId` = soubor `Templates/{id}.scriban` **v repu
  MailNotify**. Existuje `generic` (proměnné `title`, `body`, `action_url`,
  `action_text`, `footer`). Pro reset hesla použij `generic`. Nové šablony
  v MailNotify nepřidávej, to je jiné repo.
- **Odesílatel:** `Senders:{clientId}` v konfiguraci MailNotify určuje
  povolené `From`. Bez `From` se použije výchozí adresa pro zDrive.
- **Lokálně:** MailNotify jde spustit s `Auth:AllowAnonymous=true`
  (`dotnet run --project src/MailNotify.Api`, port 5092). Pro zDrive dev to
  ale není nutné (viz bod 1).

## Současný stav zDrive

- V repozitáři **není žádné odesílání e-mailů**.
- Design spec uvádí `POST /api/v1/auth/forgot-password`
  (`docs/superpowers/specs/2026-06-04-zdrive-platform-design.md`), ale
  implementovaný není.
- Hesla hashuje `Argon2PasswordHasher`. Účet s `PasswordHash == null` je jen
  přes Entra (nemá heslo, reset pro něj nedává smysl).
- Refresh tokeny: `auth.RefreshTokens` (`RefreshToken.cs`).
- Klient: `features/auth/presentation/login_page.dart`, routy v
  `lib/shared/router/app_router.dart` (`isAuthRoute`). Web běží na GitHub
  Pages. Ověř tvar URL, aby odkaz z e-mailu otevřel správnou stránku.

## Rozsah

1. **`IEmailSender`** v AuthService.Application (jinde zatím není potřeba,
   do `ZDrive.Shared` ho nedávej). Dvě implementace v Infrastructure:
   - `MailNotifyEmailSender`: podle `clients/MailNotifyClient.cs`, přes
     `IHttpClientFactory` a `TokenCredential`. Konfigurace
     `MailNotify:{BaseUrl,TenantId,ClientId,ClientSecret,Scope}`. Secret
     patří do App Settings / Key Vault, **nikdy do repa**.
   - `LoggingEmailSender`: jen zaloguje příjemce, předmět a odkaz. Použije se
     v Development, když chybí `MailNotify:BaseUrl`. Mimo Development je
     chybějící konfigurace chyba při startu (stejný vzor jako JWT klíče).
   - Výpadek MailNotify nesmí shodit request `forgot-password`. Zaloguj
     chybu (s CorrelationId) a vrať stejnou odpověď, protože uživatel stejně
     dostane generické 202.
2. `POST /api/v1/auth/forgot-password {email}`: **vždy 202**, i pro
   neexistující e-mail nebo Entra-only účet (bez e-mailu). Token je náhodný
   (32 B, base64url), v DB je jen jeho SHA-256, TTL 30 min, jednorázový.
   Nový požadavek zneplatní starší tokeny. EF migrace `AddPasswordResetTokens`
   ve schématu `auth`.
3. `POST /api/v1/auth/reset-password {token, newPassword}`: nastaví heslo a
   revokuje všechny refresh tokeny uživatele. Validace hesla stejná jako při
   registraci.
4. E-mail přes `TemplateId = "generic"`: `title`, `body`, `action_url`
   (`{ResetLinkBaseUrl}?token=...`), `action_text`, `footer`, česky nebo
   anglicky podle `Accept-Language` požadavku (jazyk uživatele v DB není).
   `Email:ResetLinkBaseUrl` je v konfiguraci.
5. Klient: odkaz „Zapomenuté heslo" na login stránce, stránka pro zadání
   e-mailu a stránka pro nové heslo (čte token z URL). Obě jsou v
   `isAuthRoute`. Lokalizace do `.arb`.
6. Rate limit: endpointy spadají pod politiku `auth` v gateway. Ověř to.
   Pokud je hotové zadání 02, platí i lockout.

## Akceptační kritéria

- [ ] Integrační testy: forgot → token v DB (hash) → reset → login novým
      heslem; starým heslem ne; starý refresh token 401. `IEmailSender`
      nahrazený fake implementací, která zachytí odkaz.
- [ ] Neexistující e-mail i Entra-only účet = stejná odpověď, žádný e-mail.
- [ ] Použitý nebo expirovaný token odmítnut.
- [ ] Unit test `MailNotifyEmailSender` přes fake `HttpMessageHandler`:
      správná URL, Bearer token, tělo podle `SendEmailRequest`. Při chybě
      MailNotify se forgot-password nerozbije.
- [ ] Flutter testy obou stránek.

## Kroky pro člověka (uveď je v popisu PR)

1. V tenantu `zcloudcz.ciamlogin.com` app registrace „zDrive → MailNotify"
   (nebo použít existující backendovou registraci zDrive), client secret,
   API permission `MailNotify API / Notify.Send` (Application) + admin
   consent. Postup: README repa MailNotify, sekce Nasazení, krok 1.3.
2. V MailNotify: `Senders__<clientId>=noreply@<doména zDrive>` a SMTP
   profil s touto adresou.
3. V App Service `zdrive-auth`: `MailNotify__*` a `Email__ResetLinkBaseUrl`.

## Výstup

Jeden PR.
