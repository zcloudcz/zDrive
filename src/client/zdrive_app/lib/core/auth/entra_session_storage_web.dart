import 'package:web/web.dart' as web;

class EntraSessionStorage {
  const EntraSessionStorage();

  void setItem(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);

  String? getItem(String key) => web.window.sessionStorage.getItem(key);

  void removeItem(String key) => web.window.sessionStorage.removeItem(key);
}
