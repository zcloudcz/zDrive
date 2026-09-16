class Diagnostics {
  static Future<void> initialize({String? version}) async {}
  static void event(String name, [Map<String, Object?> fields = const {}]) {}
  static void error(String name, Object error, [StackTrace? stack]) {}
  static Future<String?> exportLogs() async => null;
}
