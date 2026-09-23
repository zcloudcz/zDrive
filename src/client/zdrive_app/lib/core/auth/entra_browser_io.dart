/// Never reached at runtime — the Entra sign-in feature is gated by
/// [kEntraSignInVisible] (web-only), but this stub keeps non-web builds
/// compiling since `package:web` is not available there.
void navigateToEntraAuthorize(String url) {}

void stripEntraQueryFromUrl() {}
