/// Never reached at runtime — the Entra sign-in feature is gated by
/// [kEntraSignInVisible] (web-only), but this stub keeps non-web builds
/// compiling since `package:web` is not available there.
class EntraSessionStorage {
  const EntraSessionStorage();

  void setItem(String key, String value) {}

  String? getItem(String key) => null;

  void removeItem(String key) {}
}
