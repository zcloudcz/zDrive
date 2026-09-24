import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

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

/// Redirect URI for the native PKCE flow on iOS and Android (ADR 0003):
/// a custom scheme opened via ASWebAuthenticationSession / Chrome Custom
/// Tabs and received back in-process by `flutter_web_auth_2` — no server,
/// no callback page. Registered on the same 'ZCLOUD Drive Web' app
/// registration as the web origin, under its "Mobile and desktop
/// applications" platform.
const String kEntraMobileRedirectUri = 'cz.zcloud.zdrive://auth';

/// Redirect URI for the native PKCE flow on Windows (ADR 0003). Windows has
/// no registered custom-scheme handler, so this uses the loopback pattern
/// instead (RFC 8252 §7.3): `flutter_web_auth_2` opens the system browser
/// and a local HTTP listener on this fixed port catches the redirect. Entra
/// ignores the port for `http://localhost` redirect URIs, but a fixed port
/// keeps the listener deterministic.
const String kEntraWindowsRedirectUri = 'http://localhost:43823/';

/// `callbackUrlScheme` flutter_web_auth_2's Windows loopback listener
/// expects — the same host/port as [kEntraWindowsRedirectUri], without the
/// trailing slash (the plugin parses this as a URI, not a plain string
/// prefix).
const String kEntraWindowsCallbackScheme = 'http://localhost:43823';

/// Whether the "Sign in with your ZCLOUD account" button should be shown.
/// Gated behind both a configured client id AND scope — a build with a
/// client id but no scope would still redirect the user through the whole
/// Entra flow only to fail far from the cause (no `access_token` in the
/// response, or a token whose `aud` the backend rejects). Web is always
/// eligible once configured; native is additionally restricted to the
/// three released targets with an Entra redirect URI (ADR 0003) —
/// macOS/Linux have no app registration entry and stay password-only.
bool computeEntraSignInVisible({
  required bool isWeb,
  required TargetPlatform platform,
  required String clientId,
  required String scope,
}) {
  if (clientId.isEmpty || scope.isEmpty) return false;
  if (isWeb) return true;
  return platform == TargetPlatform.iOS ||
      platform == TargetPlatform.android ||
      platform == TargetPlatform.windows;
}

/// Real gate evaluated at runtime — not `const`, unlike before: telling
/// iOS/Android/Windows apart from macOS/Linux needs [defaultTargetPlatform],
/// which is a runtime getter, not a compile-time constant. [LoginPage]
/// falls back to this when its own `entraSignInVisible` param is left null.
final bool kEntraSignInVisible = computeEntraSignInVisible(
  isWeb: kIsWeb,
  platform: defaultTargetPlatform,
  clientId: kEntraClientId,
  scope: kEntraApiScope,
);

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
/// Where to send the browser next when [rootQuery] (the real URL's query
/// string — see [entraRedirectUri]) carries an Entra `code`/`error`, or
/// `null` if there's nothing to forward. Pure so the "forward once, not on
/// every rebuild" logic is unit-testable without a real browser (round 2 of
/// PR #70's review: [rootQuery] alone can't answer this on its own once the
/// caller has stripped it after forwarding — that side effect lives in
/// [stripEntraQueryFromUrl], called right after this returns non-null).
String? entraForwardTarget(Map<String, String> rootQuery, String matchedLocation) {
  final isEntraRedirect = rootQuery.containsKey('code') || rootQuery.containsKey('error');
  // Gated to '/login' specifically, not merely "not already on the callback
  // route": a real Entra redirect always lands as a fresh, hash-less page
  // load (redirect_uri has no fragment), which resolves to '/login' before
  // auth state is known. A crafted link like
  // `https://drive.zcloud.cz/?code=x&state=y#/s/<token>` would otherwise
  // hijack a public share-link visit into an Entra-callback error page on
  // every load (should-fix, round 2 of PR #70's review) — with this gate
  // its matchedLocation is '/s/<token>', not '/login', so it's ignored.
  if (!isEntraRedirect || matchedLocation != '/login') return null;
  return Uri(path: '/auth/entra-callback', queryParameters: rootQuery).toString();
}

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
