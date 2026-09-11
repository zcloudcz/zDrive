import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:zdrive_app/core/di/injection.config.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';

// Regression test for a real incident: injectable regenerated
// injection.config.dart with `isWindows: gh<bool>()` on PullSyncService and
// LocalChangeScanner, because their `isWindows` test-seam constructor
// parameter was not annotated with @ignoreParam. Nothing registers a `bool`
// with GetIt, so resolving either type — and therefore SyncCoordinator,
// which sync_page.dart resolves to open the sync page — threw at runtime.
// No existing test caught it because every other test constructs these
// classes directly rather than going through the generated DI graph. This
// test drives the *generated* `GetItInjectableX.init()` extension itself
// (not a hand-written copy of its registrations), so a future regeneration
// that reintroduces an unregistered dependency fails here.
void main() {
  late Directory tempDir;
  late GetIt container;

  setUp(() async {
    // AppPreferences is registered with `preResolve: true`, so the
    // generated init() awaits `Hive.openBox` immediately, before this test
    // gets a chance to touch anything. A temp directory is the smallest way
    // to make that succeed in a plain `flutter test` run, which has no
    // platform channels to back path_provider/hive_flutter with.
    tempDir = await Directory.systemTemp.createTemp('zdrive_sync_di_test');
    Hive.init(tempDir.path);

    // A fresh GetIt instance, not the global `getIt` — this test must not
    // leak real registrations into, or steal them from, other test files
    // that run in the same process.
    container = GetIt.asNewInstance();
    await container.init();
  });

  tearDown(() async {
    await container.reset();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test(
      'generated DI graph resolves PullSyncService, LocalChangeScanner and SyncCoordinator',
      () {
    expect(container<PullSyncService>(), isA<PullSyncService>());
    expect(container<LocalChangeScanner>(), isA<LocalChangeScanner>());
    expect(container<SyncCoordinator>(), isA<SyncCoordinator>());
  });
}
