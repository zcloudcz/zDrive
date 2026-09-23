import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-time client id of Drive's own Entra SPA app registration (ADR
/// 0002 — each app registers itself with Entra directly, no token broker).
/// Empty by default: no production registration exists yet, and an empty
/// id is exactly what keeps [kEntraSignInVisible] false.
/// Pass at build time: flutter build web --dart-define=ENTRA_CLIENT_ID=(guid)
const String kEntraClientId = String.fromEnvironment('ENTRA_CLIENT_ID');

/// Build-time API scope requested from Entra alongside `openid`, e.g.
/// `api://<drive-api-app-id>/access_as_user`. The exact value depends on how
/// the API app registration exposes its scope — set by whoever does that
/// registration, not guessed here.
/// Pass at build time: flutter build web --dart-define=ENTRA_API_SCOPE=(scope)
const String kEntraApiScope = String.fromEnvironment('ENTRA_API_SCOPE');

// Pilot tenant from docs/identity-pilot.md, reused as-is for the production
// registration per ADR 0002 (same tenant, same zcloud_signin user flow).
// Not a secret — a tenant id only identifies a public Entra endpoint.
const String _entraTenantId = '37a15516-3c13-4bc8-a606-63226859b29a';
const String _entraHost = 'zcloudcz.ciamlogin.com';

const String entraAuthorizeUrl =
    'https://$_entraHost/$_entraTenantId/oauth2/v2.0/authorize';
const String entraTokenUrl =
    'https://$_entraHost/$_entraTenantId/oauth2/v2.0/token';

/// Whether the "Sign in with your ZCLOUD account" button should be shown.
/// Direct browser PKCE against Entra is web-only, and gated behind both a
/// configured client id AND scope — a build with a client id but no scope
/// would still redirect the user through the whole Entra flow only to fail
/// far from the cause (no `access_token` in the response, or a token whose
/// `aud` the backend rejects). Neither exists until a production Entra app
/// registration is done.
const bool kEntraSignInVisible = kIsWeb && kEntraClientId != '' && kEntraApiScope != '';

/// Pure form of the [kEntraSignInVisible] gate, so the "needs both, not
/// just one" rule is unit-testable without juggling `--dart-define` per
/// test case (those three consts are fixed for the whole `flutter test`
/// process).
bool computeEntraSignInVisible({required bool isWeb, required String clientId, required String scope}) =>
    isWeb && clientId != '' && scope != '';

/// The `redirect_uri` sent to Entra: this app's plain origin, no path.
///
/// Two constraints rule out a dedicated path like `/auth/entra-callback`
/// here (review round 1 of PR #70 caught both):
/// - OAuth forbids a fragment in `redirect_uri` (RFC 6749 §3.1.2), so a
///   client-side hash route (this app uses hash-based routing — no
///   `usePathUrlStrategy()` — see `share_dialog.dart`'s `#/s/...` links for
///   the same pattern) can never be the registered value.
/// - A real path *would* be legal, but GitHub Pages serves this app with no
///   SPA fallback (`deploy-web.yml` uploads a plain `build/web`, no
///   `404.html` rewrite): Entra navigating the browser straight to
///   `origin/auth/entra-callback?code=...` gets Pages' own 404, and the app
///   never loads to handle it.
///
/// The origin root is the one URL Pages always serves. `code`/`state`/
/// `error` land in its real query string, which coexists with the hash
/// fragment go_router reads — `app_router.dart`'s `redirect` callback reads
/// them from [Uri.base] on first load and forwards them into the in-app
/// `/auth/entra-callback` hash route.
String entraRedirectUri() {
  final base = Uri.base;
  // Uri.replace(query: '', fragment: '') does NOT clear these — it sets
  // them to present-but-empty, which still serializes as a trailing "?#"
  // (verified: https://drive.zcloud.cz/#/login -> ".../?#"). Entra compares
  // redirect_uri as an exact string, so that would never match what gets
  // registered. Omitting query/fragment from the constructor entirely is
  // the only way to actually drop them.
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '/',
  ).toString();
}
