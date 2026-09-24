# 0003 — Entra sign-in on iOS, Android and Windows

## Status

Accepted.

## Context

ADR 0002 added Entra sign-in to the **web** client only: a hand-rolled
authorization code + PKCE flow (`lib/core/auth/entra_pkce.dart`,
`entra_sign_in.dart`, `entra_token_exchange.dart`) that redirects the whole
tab to Entra and comes back to the app's origin. The backend side
(`POST /api/v1/auth/entra`, `(tid, oid)` → local user, fresh tenant per
identity, 24 h absolute session cap) is platform-neutral and already live.

Native clients still only have email + password. Since Drive's owner decided
legacy accounts are not linked (ADR 0002 / `identity-production-rollout.md`),
a user who signed up through Entra on the web has **no password** and cannot
sign in on iOS, Android or the Windows desktop sync client at all.

Released native targets: iOS (TestFlight), Android (APK/AAB), Windows
(installer). macOS has no distribution yet. `ZDrive.BackupCli` is a headless
tool.

Numbers: < 100 MAU, three native targets, one existing Entra tenant and app
registration (`ZCLOUD Drive Web`, client id `4a1e6c55-…`). Not a scale
problem — the constraints are OS browser APIs and redirect-URI rules.

## Decision

Reuse the existing PKCE, CSRF-state and token-exchange code unchanged; only
replace **how the browser is opened and how the redirect comes back**, using
one package: [`flutter_web_auth_2`](https://pub.dev/packages/flutter_web_auth_2).

| Platform | Browser | Redirect URI | Mechanism |
|---|---|---|---|
| iOS | `ASWebAuthenticationSession` | `cz.zcloud.zdrive://auth` | custom scheme |
| Android | Chrome Custom Tabs | `cz.zcloud.zdrive://auth` | custom scheme, `CallbackActivity` intent filter |
| Windows | system browser | `http://localhost:43823/` | loopback listener (RFC 8252 §7.3) |
| Web | full-page redirect | origin root | unchanged (ADR 0002) |

Same Entra app registration and client id for all platforms: add a
**Mobile and desktop applications** platform to `ZCLOUD Drive Web` with the
two redirect URIs above. Tokens for native redirect URIs are redeemed without
the SPA CORS requirement, so the existing Dio token POST works unchanged.
Entra ignores the port for `http://localhost` on that platform; a fixed port
is still used so the listener is deterministic.

### Session renewal on native (new)

The 24 h absolute cap on an Entra-derived zDrive session is deliberate
(revocation on the Entra side must take effect). On web the user re-signs in.
On Windows the app autostarts hidden and syncs unattended — without renewal
sync would silently stop every day.

Native clients additionally request `offline_access`, store the **Entra
refresh token** in `flutter_secure_storage` (same store as zDrive tokens),
and when the zDrive refresh fails because the cap was hit, they silently
redeem the Entra refresh token at Entra's token endpoint and call
`/auth/entra` again. Revocation is preserved: a revoked/disabled Entra user
gets an error from Entra itself and falls back to the login screen. Only
when that silent path fails does the user see the login page.

Web does **not** store the Entra refresh token (no secure storage in a
browser; XSS would expose a long-lived credential) — unchanged behaviour.

## Seams

| Component | Change |
|---|---|
| Backend | none |
| `entra_config.dart` | visibility gate becomes platform-aware (web, iOS, Android, Windows); native redirect URI constants |
| `entra_sign_in.dart` | split "open browser + receive callback" behind an interface: web impl = current redirect, native impl = `flutter_web_auth_2` |
| `EntraCallbackPage` | web only; native completes in-process (`authenticate()` returns the callback URL) |
| `TokenStorage` | + Entra refresh token (native only) |
| Auth refresh path | on zDrive refresh failure with a stored Entra refresh token → silent re-exchange, else logout as today |
| Platform config | iOS: none needed for ASWebAuthenticationSession callback scheme; Android: `CallbackActivity` intent filter in `AndroidManifest.xml`; Windows: none |
| CI | `release-clients.yml` (Android, Windows) and `scripts/Build-IosRelease.sh` pass `ENTRA_CLIENT_ID` / `ENTRA_API_SCOPE` from repo vars, same as `deploy-web.yml` |

## Failure modes

- **User cancels the browser sheet**: `flutter_web_auth_2` throws a cancel
  exception → back to login page, no error dialog.
- **Loopback port 43823 busy on Windows**: sign-in fails with a readable
  error; password login still works. Not worth port negotiation at this scale.
- **State mismatch / Entra `error=`**: same handling as web (shared code).
- **Entra refresh token revoked or expired**: silent renewal fails → normal
  logout → login page. Sync stops until the user signs in again — correct.
- **App registration missing the native platform**: Entra returns
  `AADSTS50011` in the browser; feature stays gated by the same build-time
  defines, so an unset/misconfigured build shows no button.
- **Rollback**: unset `ENTRA_CLIENT_ID` repo var and re-release — the button
  disappears; password login is never removed by this change.

## NOT list

- **macOS** — no distribution exists; the same package supports it, add with
  its release.
- **`ZDrive.BackupCli`** — keeps password login. Trigger: an Entra-only user
  needs the CLI (device code flow would be the fit).
- **Account linking / password for Entra users** — owner decision stands.
- **MSAL native SDKs** — pure-Dart PKCE is already written and reviewed;
  MSAL would add two native SDKs for no new capability.
- **Removing password login** — separate decision, per rollout doc.

## Implementation plan (for the implementing agent)

One PR, `feat/native-entra-sign-in`:

1. Add `flutter_web_auth_2` (pin version, update `pubspec.lock`).
2. `entra_config.dart`: `computeEntraSignInVisible` takes a platform
   (web/iOS/Android/Windows → eligible; macOS/Linux → not). Native redirect
   URIs as constants. Keep `entraRedirectUri()` for web.
3. Abstract the browser step: `EntraBrowserFlow` with web impl (existing
   redirect + callback route) and native impl (`FlutterWebAuth2.authenticate`
   with `callbackUrlScheme: 'cz.zcloud.zdrive'` on mobile, `'http://localhost:43823'`
   on Windows). Native impl parses `code`/`state`/`error` from the returned
   URL and reuses the exact same state check + token exchange + `EntraLoginRequested`.
4. Native scope = `openid offline_access <ENTRA_API_SCOPE>`; store the
   returned `refresh_token` in `TokenStorage` (native only; web keeps not
   requesting `offline_access`).
5. Auth refresh path (`auth_interceptor.dart` / `AuthRepository`): when the
   zDrive refresh call fails and an Entra refresh token exists → POST
   `grant_type=refresh_token` to Entra's token endpoint → new access token →
   `/auth/entra` → save tokens → retry the original request. Rotate the
   stored Entra refresh token if a new one is returned. On any failure:
   clear it and fall through to today's logout. Logout clears it too.
6. Android `AndroidManifest.xml`: `com.linusu.flutter_web_auth_2.CallbackActivity`
   with intent filter for scheme `cz.zcloud.zdrive`.
7. CI: pass both defines in `release-clients.yml` (Android apk/aab, Windows)
   and `Build-IosRelease.sh` (its `DART_DEFINE` becomes multiple
   `--dart-define` args), from `vars.ENTRA_CLIENT_ID` / `vars.ENTRA_API_SCOPE`.
8. Update `CLAUDE.md` build-defines table.
9. Tests: gate per platform; native flow parses callback URL (success,
   state mismatch, `error=`, user cancel) with `FlutterWebAuth2` behind a
   fake; silent renewal (success path retries the request; revoked refresh
   token → logout; web never stores/uses an Entra refresh token; logout
   clears it). `flutter analyze --fatal-infos` + full `flutter test` green.

Human step (Entra admin center, `ZCLOUD Drive Web` → Authentication → Add a
platform → **Mobile and desktop applications**): redirect URIs
`cz.zcloud.zdrive://auth` and `http://localhost`. No new client id, no new
scope.
