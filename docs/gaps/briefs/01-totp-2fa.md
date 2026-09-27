# Zadání 01: TOTP dvoufázové ověření (2FA)

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers, migrace přes
> `--startup-project src/services/Api`, komunikace česky, kód anglicky.
> Pokud je něco v zadání nejasné nebo neodpovídá kódu, zastav se a zeptej se.

## Cíl

Uživatel s heslem si může zapnout TOTP 2FA (Google Authenticator,
Microsoft Authenticator, 1Password…). Po zapnutí přihlášení heslem
vyžaduje i šestimístný kód. Součástí jsou jednorázové záložní kódy.

## Současný stav

- `src/services/AuthService/ZDrive.AuthService.Application/Commands/Login/LoginCommandHandler.cs`:
  po `IPasswordHasher.Verify` (~ř. 27) rovnou vydá access + refresh token.
  Špatné přihlašovací údaje záměrně vrací 404 (`NotFoundException`).
- `User` (`AuthService.Domain/Entities/User.cs`) nemá žádná 2FA pole.
  `PasswordHash == null` znamená účet jen přes Entra.
- Migrace: `AuthService/ZDrive.AuthService.Infrastructure/Migrations/`,
  schéma `auth`, poslední `20260918103321_AddExternalIdentities`.
- Endpointy: `src/services/Api/Controllers/Auth/AuthController.cs`,
  `UsersController.cs`. Odpovědi jsou obalené `ApiResponse<T>`.
- Klient: stav je v `lib/core/auth/auth_bloc.dart` (stavy AuthInitial,
  AuthLoading, Authenticated, Unauthenticated, AuthError). Login DTO je v
  `lib/features/auth/data/auth_dtos.dart`, repository v
  `auth_repository_impl.dart`, stránka `features/auth/presentation/login_page.dart`,
  router `lib/shared/router/app_router.dart` (seznam `isAuthRoute` ř. 46-49).
- Testy: `src/services/AuthService.Tests` (unit s EF InMemory + `Fakes/`,
  integrační `Integration/AuthServiceFactory.cs`, `AuthFlowTests`).
  Klient `test/core/auth/auth_bloc_test.dart`,
  `test/features/auth/presentation/login_register_pages_test.dart`.

## Rozsah

**Backend**
1. Doménový model: TOTP secret (šifrovaný at-rest přes ASP.NET Core Data
   Protection, ne plain text), `TwoFactorEnabledAt`, tabulka záložních kódů
   (hash, použitý ano/ne). EF migrace `AddTwoFactor`.
2. Enrollment (autorizované, jen pro účty s heslem):
   - `POST /api/v1/users/me/2fa/setup` vrátí secret + `otpauth://` URI.
     Zatím neaktivní.
   - `POST /api/v1/users/me/2fa/confirm {code}` aktivuje 2FA a vrátí
     10 záložních kódů. Zobrazí se jen jednou.
   - `POST /api/v1/users/me/2fa/disable {password, code}`.
   - `GET /api/v1/users/me` rozšířit o `twoFactorEnabled`.
3. Login: pokud má uživatel 2FA, `login` po ověření hesla **nevydá tokeny**.
   Vrátí `{ twoFactorRequired: true, challengeToken }`, kde `challengeToken`
   je krátkodobý (5 min) a jednorázový. Dokončí se přes
   `POST /api/v1/auth/login/2fa {challengeToken, code | recoveryCode}`.
   Challenge ukládej do DB, ne jen jako podepsaný JWT, aby šla zneplatnit
   po použití.
4. TOTP podle RFC 6238 (SHA-1, 6 číslic, 30 s, tolerance ±1 krok). Doporučená
   knihovna je `Otp.NET` (MIT). Stejný kód nesmí projít dvakrát (ulož
   poslední použitý time-step).
5. Entra přihlášení 2FA neřeší. MFA pro Entra účty se zapíná v Entra
   (Conditional Access + e-mail OTP nebo passkey, viz
   `docs/gaps/entra-external-id.md`). Stránka nastavení 2FA se Entra-only
   účtům (bez hesla) nezobrazuje.

**Klient**
1. Nový stav `AuthTwoFactorRequired(challengeToken)` a event
   `TwoFactorCodeSubmitted`. Login DTO rozlišuje obě odpovědi.
2. Krok na zadání kódu (inline v `LoginPage` nebo route `/login/2fa`
   přidaná do `isAuthRoute`), s odkazem „použít záložní kód".
3. Nastavení 2FA v menu účtu: QR kód (balíček `qr_flutter`, BSD-3) +
   ruční secret, potvrzení kódem, zobrazení záložních kódů s kopírováním,
   vypnutí.
4. Lokalizace: všechny nové texty do `lib/shared/l10n/app_*.arb`. Stačí
   `cs` a `en`, ostatní jazyky převezmou `en`, pokud to projekt tak dělá.
   Ověř, jak se chovají chybějící klíče.

## Mimo rozsah

WebAuthn/passkeys, SMS, vynucení 2FA pro tenant, obnova hesla, rate
limiting (to je zadání 02).

## Akceptační kritéria

- [ ] Uživatel bez 2FA se přihlašuje beze změny (zpětná kompatibilita
      odpovědi `login`: nová pole jen přidaná).
- [ ] S 2FA: heslo → challenge → kód → tokeny. Špatný kód = 400/401 bez
      tokenů. Expirovaný nebo už použitý challenge = odmítnut.
- [ ] Záložní kód funguje jednou.
- [ ] Stejný TOTP kód nejde použít dvakrát.
- [ ] Secret v DB není čitelný jako plain text.
- [ ] Integrační testy (Testcontainers Postgres) pro každý nový endpoint:
      happy path + error path. Unit testy handlerů.
- [ ] Flutter testy: bloc (nové přechody), login stránka (krok s kódem),
      stránka nastavení.
- [ ] `dotnet test` a `flutter analyze` + `flutter test` zelené.

## Výstup

Jeden PR s popisem změn API (nové endpointy a tvar odpovědi `login`).
