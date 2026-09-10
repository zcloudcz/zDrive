import 'dart:io';

import 'package:injectable/injectable.dart';

/// SyncService's `DevicePlatform` enum ordinals (Windows=0, MacOS=1,
/// Android=2, iOS=3, Web=4) — see the comment on
/// [SyncRemoteDataSource.registerDevice] for why this has to be the ordinal,
/// not the name. Only the two ordinals this app actually registers as are
/// named here.
const platformOrdinalWindows = 0;
const platformOrdinalMacOS = 1;

/// This machine's identity for device registration, isolated in its own
/// class so [DeviceRegistrationService] can be unit-tested without being at
/// the mercy of which OS the test happens to run on (CI runs `flutter test`
/// on Linux, which is neither Windows nor macOS).
@lazySingleton
class CurrentDevicePlatform {
  int get ordinal {
    if (Platform.isWindows) return platformOrdinalWindows;
    if (Platform.isMacOS) return platformOrdinalMacOS;
    throw UnsupportedError('Designated-folder sync only targets Windows and macOS.');
  }

  String get name {
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) return hostname;
    } catch (_) {
      // Platform.localHostname can throw on some setups; fall through.
    }
    return Platform.isWindows ? 'Windows device' : 'Mac device';
  }
}
