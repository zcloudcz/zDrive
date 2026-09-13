import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;

// Returns the future from the generated init() and callers MUST await it.
// AppPreferences is registered with `preResolve: true` (it opens a Hive box),
// so init() suspends at that registration and everything declared after it is
// still unregistered when the future is pending. Discarding it made the app
// start against a half-built container: on native the box opens fast enough to
// hide the race, on web IndexedDB is a real async round trip and the first
// widget to resolve a late-registered type threw "not registered inside GetIt".
@InjectableInit()
Future<void> configureDependencies() => getIt.init();
