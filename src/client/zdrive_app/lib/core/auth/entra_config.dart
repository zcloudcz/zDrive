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
/// Direct browser PKCE against Entra is web-only, and gated behind a
/// configured client id so the whole feature is unreachable until a
/// production Entra app registration exists — the default build has none.
const bool kEntraSignInVisible = kIsWeb && kEntraClientId != '';

/// This app's own callback path, appended to its current origin to build the
/// `redirect_uri` sent to Entra. Only meaningful on web, where [Uri.base] is
/// the browser's current URL.
String entraRedirectUri() => Uri.base
    .replace(path: '/auth/entra-callback', query: '', fragment: '')
    .toString();
