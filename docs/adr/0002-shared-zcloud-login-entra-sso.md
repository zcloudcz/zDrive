# 0002 — zcloud-login as an account chooser, not a token broker

## Status

Proposed.

## Context

`docs/identity-production-rollout.md` already decided to use the Entra
External ID tenant (`ZCLOUD Users`) as Drive's identity provider, and Drive's
backend adapter is largely built: `AuthService`'s `POST /api/v1/auth/entra-
exchange` validates an Entra access token, maps `(tid, oid)` to a local user
(fresh tenant per identity — no account linking for Drive, per the owner's
18 September decision), and issues the normal zDrive JWT. It sits behind
`Entra:Enabled=false` and returns 404 while off. What's missing is the
client side: no Flutter code acquires an Entra token yet, and no production
Entra app registration exists for Drive (only the `localhost:8081` pilot).

Separately, `zcloud-login` (`C:\GIT\ZCLOUD\zcloud-login`) is a standalone
Vite SPA published to GitHub Pages. Its own README states it "does not
manage passwords or connect to Print or Drive" — today it is a demo that
proves Entra sign-in works, not a component any app depends on.

The request this ADR answers: wire Drive's web client to sign in through
`zcloud-login`, so "Drive redirects to zcloud-login, it runs the Entra flow,
and hands a session back to Drive" — the explicit goal being one shared
login screen across ZCLOUD apps (Drive, and later Print), not a Drive-only
look.

Numbers: fewer than 100 monthly active Drive users today (per the rollout
doc), one web client in scope now (Print's web frontend exists but its API
source is still unlocated, so it is out of scope for this ADR). This is not
a scale problem — nothing here needs to survive load, it needs to not leak
a credential across two browser origins.

## Decision

**Do not build zcloud-login into a token broker.** Each app (Drive, later
Print) keeps its own Entra app registration and calls Entra directly with
authorization code + PKCE, exactly as `identity-production-rollout.md`
already specified for Drive. `zcloud-login` becomes an **account chooser**:
a landing page that links out to each app's own sign-in entry point
(`https://drive.zcloud.cz/login`, later a Print equivalent). It never
acquires, stores, or forwards a token belonging to another app.

The "one shared login screen" feeling the request actually wants is already
bought, not built: Entra External ID serves the same Microsoft-hosted,
branded sign-in page (`zcloudcz.ciamlogin.com`, the logo and copy already
configured on the `zcloud_signin` user flow in the pilot) to every app
registered against that tenant/user flow. Because it is one hosted page on
one origin, Entra also keeps one SSO session cookie there — a user who
already authenticated for Drive and then opens Print gets silently signed
in (`prompt=none`) without seeing a login form again, no custom code
required. That is the actual mechanism for "shared login across apps," and
it is Entra's, not zcloud-login's.

### Why not the literal ask (zcloud-login runs the flow and hands Drive a token)

An MSAL access token is scoped to a specific `aud` (audience) — the API app
registration the token was requested for. A token `zcloud-login` acquires
for itself (or for Graph) is not valid at Drive's `entra-exchange` endpoint,
which checks audience and required scope. Making that work would require
either:

- `zcloud-login` requesting Drive's own API scope on Drive's behalf, which
  makes `zcloud-login` a pre-authorized client for every app's scopes — one
  compromised origin (XSS, dependency, GitHub Pages build supply chain)
  becomes able to mint valid tokens for Drive *and* every future app; or
- a custom hand-off protocol (redirect with a code/token in the URL,
  `postMessage`, or a short-lived broker session) between two different
  origins — exactly the shape most token-leak and open-redirect CVEs come
  from, and it would need its own threat-modeling, expiry, and replay
  protection that Entra already provides for free at the "buy identity"
  rung of the ladder.

Building that is buying a security liability to reproduce something the
identity provider already does. Rejected.

## Seams

| Component | Owns | Does not own |
|---|---|---|
| Entra External ID (`zcloudcz.ciamlogin.com`) | Credential entry, session cookie, SSO across apps registered to `zcloud_signin`, token issuance per audience | Any app's local user/tenant model |
| `zcloud-login` | A links-out landing page only (which apps exist, where to start) | Tokens, sessions, app data, any app's callback |
| Drive web client (new) | Its own Entra app registration + redirect URI, MSAL auth code + PKCE, calls `entra-exchange` with its own audience-scoped token | Print's registration or tokens |
| AuthService (`entra-exchange`, already built) | `(tid, oid)` → local user mapping, zDrive JWT issuance, 24h capped session per the existing handler | Entra token validation internals (delegated to `IEntraTokenValidator`) |

## Failure modes

- **No active Entra SSO session** (first visit, or session cookie expired):
  normal login prompt on Entra's hosted page — same as today's pilot, not a
  new failure mode.
- **Entra access revoked mid-session**: the existing 24h absolute session
  cap on the zDrive-issued token (already in `EntraExchangeCommandHandler`)
  bounds how long a revoked identity keeps working — unchanged by this ADR.
- **`zcloud-login` compromised** (XSS, Pages build supply chain): blast
  radius is limited to a fake "continue to Drive/Print" link — it holds no
  token and no session, so it cannot forge access to either app. This is
  the property the rejected token-broker design would have given up.
- **Drive's Entra app registration misconfigured** (wrong redirect URI,
  wrong scope): auth code exchange fails client-side with a normal OAuth
  error; `entra-exchange` never gets an invalid audience because the token
  was never issued for the wrong `aud` in the first place — the failure is
  visible at the point closest to the misconfiguration, not deep in
  AuthService.
- **Rollback**: `Entra:Enabled=false` (already the default) turns the
  endpoint back to 404 instantly. No data migration to undo, since Drive
  keeps issuing its own JWTs unconditionally either way and Entra users are
  simply new local users (per the existing no-linking decision).

## NOT list

- **Not building**: any token hand-off between `zcloud-login` and Drive, a
  session broker service, `postMessage`/redirect-with-token protocol,
  shared token storage. Trigger to revisit: only if a future requirement
  genuinely needs one **origin** to hold the session for multiple apps
  server-side (e.g. a true unified SPA shell embedding Drive/Print as
  iframes) — not indicated by anything in scope today.
- **Not touching Print** in this ADR: its API source and account-linking
  decision are still open per `identity-production-rollout.md`; it adopts
  the same seam (own registration, own redirect) once unblocked.
- **Not changing `zcloud-login`'s current build/deploy** beyond adding
  outbound links — it stays a static GitHub Pages SPA, no backend added.
- **Not implementing Google production publishing** — still gated on
  Google's Testing-mode restriction per the existing rollout doc; out of
  scope here.

## Migration order

1. Register Drive's own production Entra SPA app (redirect URI =
   `https://drive.zcloud.cz/auth/callback` or equivalent), reusing the
   existing `zcloud_signin` user flow and branding — no new tenant, no new
   user flow.
2. Add MSAL-based sign-in to the Flutter web client: authorization code +
   PKCE against Drive's new registration, then `POST /api/v1/auth/entra-
   exchange` with the resulting access token. Keep the existing
   password login path untouched and reachable (BackupCli and desktop/
   mobile clients still use it; this ADR does not change them).
3. Flip `Entra:Enabled=true` for a small set of named test users first (per
   `identity-production-rollout.md`'s staged-release gate), verify the
   already-written invalid-issuer/audience/tenant/expiry tests hold against
   the real tenant, not just the fakes.
4. Add the account-chooser links in `zcloud-login` pointing at Drive's (and
   later Print's) own login entry points. This step has no dependency on
   steps 1–3 landing first — it can ship independently since it only ever
   links out.
5. Expand to all Drive users once login/link failure monitoring (already
   specified in the rollout doc's step 5) shows no unexpected denial rate.

## References

- `docs/identity-pilot.md`, `docs/identity-production-rollout.md` — prior
  decisions this ADR builds on, not repeats.
- `src/services/AuthService/ZDrive.AuthService.Application/Commands/
  EntraExchange/` — existing, tested backend adapter this ADR reuses as-is.
- `C:\GIT\ZCLOUD\zcloud-login\README.md` — current state of the account
  portal this ADR scopes down to "links out only."
