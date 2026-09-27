# Zadání 03: Obnova hesla e-mailem

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers, migrace přes
> `--startup-project src/services/Api`, komunikace česky, kód anglicky.
> Pokud je něco v zadání nejasné nebo neodpovídá kódu, zastav se a zeptej se.

> **Předpoklad:** vlastník produktu rozhodl o poskytovateli e-mailu
> (`docs/gaps/README.md`, rozhodnutí 3.1). Pokud v zadání není doplněné,
> implementuj jen abstrakci + SMTP a provider nech jako konfiguraci.

## Cíl

„Zapomněl jsem heslo" → e-mail s odkazem → nastavení nového hesla.

## Současný stav

- V repozitáři **není žádné odesílání e-mailů** (ani MailKit, SendGrid, ACS).
  Jediná zmínka je enum `NotificationChannel.Email` v NotificationService.
- Design spec uvádí `POST /api/v1/auth/forgot-password`
  (`docs/superpowers/specs/2026-06-04-zdrive-platform-design.md`), ale
  implementovaný není.
- Hesla hashuje `Argon2PasswordHasher` (Isopoh.Cryptography.Argon2).
  Účet s `PasswordHash == null` je jen přes Entra.
- Klient: `features/auth/presentation/login_page.dart`, routy v
  `lib/shared/router/app_router.dart` (`isAuthRoute`). Web běží na GitHub
  Pages s hash/path routingem. Ověř, jak vypadá URL, aby odkaz z e-mailu
  otevřel správnou stránku.

## Rozsah

1. `IEmailSender` v `ZDrive.Shared` (nebo v AuthService.Application, pokud
   ho zatím nikdo jiný nepotřebuje). Implementace přes MailKit, konfigurace
   `Email:Smtp:{Host,Port,User,Password,From}`. Bez konfigurace se v
   Development jen loguje obsah e-mailu, mimo Development je to chyba při
   startu. Stejný vzor jako JWT klíče.
2. `docker-compose.yml`: přidat Mailpit (`axllent/mailpit`, UI na portu 8025)
   a nastavit na něj Api.
3. `POST /api/v1/auth/forgot-password {email}`: vždy 202, i pro neexistující
   e-mail. Token je náhodný (32 B), v DB se ukládá jen jeho hash, TTL 30 min,
   jednorázový. Nový požadavek zneplatní starší tokeny. Pro Entra-only účet
   se e-mail nepošle (nebo pošle informaci, že se přihlašuje přes ZCLOUD
   účet; vyber a zdůvodni).
4. `POST /api/v1/auth/reset-password {token, newPassword}`: nastaví heslo,
   revokuje všechny refresh tokeny uživatele. Validace hesla stejná jako
   při registraci.
5. E-mail: prostý HTML + text, česky a anglicky podle jazyka. Pokud jazyk
   uživatele v DB není, použij `Accept-Language` z požadavku. Base URL
   klienta z konfigurace (`Email:ResetLinkBaseUrl`).
6. Klient: odkaz „Zapomenuté heslo" na login stránce, stránka pro zadání
   e-mailu a stránka pro nové heslo (čte token z URL). Obě jsou v
   `isAuthRoute`. Lokalizace do `.arb`.
7. Rate limit: endpointy spadají pod politiku `auth` v gateway. Ověř to.

## Akceptační kritéria

- [ ] Integrační testy: forgot → token v DB (hash) → reset → login novým
      heslem; starým heslem ne; starý refresh token 401.
- [ ] Neexistující e-mail = stejná odpověď, žádný e-mail.
- [ ] Použitý nebo expirovaný token odmítnut.
- [ ] Test `IEmailSender` přes fake. SMTP implementace ověřená proti
      Mailpitu z Testcontainers, nebo aspoň lokálně (popsat v PR).
- [ ] Flutter testy obou stránek.

## Výstup

Jeden PR. V popisu uveď, co je potřeba nastavit v produkci (SMTP secrets do
App Service / Key Vault).
