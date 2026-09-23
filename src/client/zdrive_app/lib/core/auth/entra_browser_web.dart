import 'package:web/web.dart' as web;

void navigateToEntraAuthorize(String url) => web.window.location.assign(url);

/// Drops Entra's `code`/`state`/`error` off the real URL (its query string,
/// not the `#...` hash go_router owns), keeping the current hash untouched.
///
/// Round 2 of PR #70's review: the browser's hash-routing URL strategy
/// re-serializes the real query string on every in-app navigation
/// (`HashUrlStrategy.prepareExternalUrl` includes `location.search`
/// unconditionally), so leaving it in place made every subsequent
/// `GoRouter.redirect` call see `code` again — forwarding to
/// `/auth/entra-callback` on every rebuild, including right after a
/// successful sign-in navigated to `/home/files`, which go_router detects
/// as a redirect loop and fails the whole navigation. Stripping the query
/// string right after the one-time forward is what actually makes the
/// forward a one-time thing, and also means an F5 mid-flow lands on a plain
/// URL instead of re-submitting an already-consumed code.
void stripEntraQueryFromUrl() {
  final location = web.window.location;
  web.window.history.replaceState(null, '', '${location.pathname}${location.hash}');
}
