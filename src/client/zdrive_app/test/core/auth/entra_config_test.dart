import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/auth/entra_config.dart';

void main() {
  test('kEntraSignInVisible is false by default — no ENTRA_CLIENT_ID is '
      'passed in a normal `flutter test` run, and no production Entra app '
      'registration exists yet (ADR 0002)', () {
    expect(kEntraClientId, isEmpty);
    expect(kEntraSignInVisible, isFalse);
  });
}
