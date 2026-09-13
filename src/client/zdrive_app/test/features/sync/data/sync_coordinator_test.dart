import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/sync/data/device_id_storage.dart';
import 'package:zdrive_app/features/sync/data/device_registration_service.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/domain/sync_mirror_repository.dart';

class MockPullSyncService extends Mock implements PullSyncService {}

class MockLocalChangeScanner extends Mock implements LocalChangeScanner {}

class MockSyncMirrorRepository extends Mock implements SyncMirrorRepository {}

class MockDeviceIdStorage extends Mock implements DeviceIdStorage {}

class MockAppPreferences extends Mock implements AppPreferences {}

class MockDeviceRegistrationService extends Mock implements DeviceRegistrationService {}

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

void main() {
  late MockPullSyncService mockPull;
  late MockLocalChangeScanner mockScanner;
  late MockSyncMirrorRepository mockMirror;
  late MockDeviceIdStorage mockDeviceIdStorage;
  late MockAppPreferences mockPreferences;
  late MockDeviceRegistrationService mockDeviceRegistration;
  late MockSyncRemoteDataSource mockRemote;
  late SyncCoordinator coordinator;
  late Directory tempDir;
  late String syncPath;

  setUp(() {
    mockPull = MockPullSyncService();
    mockScanner = MockLocalChangeScanner();
    mockMirror = MockSyncMirrorRepository();
    mockDeviceIdStorage = MockDeviceIdStorage();
    mockPreferences = MockAppPreferences();
    mockDeviceRegistration = MockDeviceRegistrationService();
    mockRemote = MockSyncRemoteDataSource();
    coordinator = SyncCoordinator(
      mockPull,
      mockScanner,
      mockMirror,
      mockDeviceIdStorage,
      mockPreferences,
      mockDeviceRegistration,
      mockRemote,
    );
    // A real, existing directory — syncOnce checks for that before doing
    // anything else (F3), so a bare string like '/local/sync' that does
    // not exist on the test runner's filesystem would fail every test in
    // this file, not just the one added for that check below.
    tempDir = Directory.systemTemp.createTempSync('sync_coordinator_test_');
    syncPath = tempDir.path;

    when(() => mockMirror.clearAll()).thenAnswer((_) async {});
    when(() => mockDeviceIdStorage.clear()).thenAnswer((_) async {});
    when(() => mockPreferences.clearSyncFolderPath()).thenAnswer((_) async {});
    when(() => mockPreferences.setSyncOwnerUserId(any())).thenAnswer((_) async {});
    when(() => mockPreferences.setSyncFolderPath(any())).thenAnswer((_) async {});
    // syncOnce now no-ops when its argument differs from the stored sync
    // folder path (finding 3 below) — every test in this file that calls
    // syncOnce(syncPath) needs the two to agree by default, unless a test
    // is specifically exercising that mismatch.
    when(() => mockPreferences.syncFolderPath).thenReturn(syncPath);
    // Default: a registered device whose heartbeat succeeds. Deliberately
    // NOT the "no device yet" path — defaulting to null would send every
    // test that doesn't care about the heartbeat down the early-return
    // branch, so a regression that moved the heartbeat above a guard, or
    // fired it on a failed run, would keep the whole file green. The
    // first-run case is stubbed explicitly by the one test that wants it.
    when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'device-default');
    when(() => mockRemote.heartbeat(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('syncOnce pulls, then scans — each step strictly completes before '
      'the next starts', () async {
    final callOrder = <String>[];
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async {
      callOrder.add('pull');
      return 3;
    });
    when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async {
      callOrder.add('scan');
      return 2;
    });

    final result = await coordinator.syncOnce(syncPath);

    expect(callOrder, ['pull', 'scan']);
    expect(result.pulled, 3);
    expect(result.pushed, 2);
  });

  test('two concurrent syncOnce calls run pull and scan exactly once — the '
      'second call awaits the first instead of racing it', () async {
    final gate = Completer<int>();
    var pullCalls = 0;
    var scanCalls = 0;
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async {
      pullCalls++;
      // Held open until the test releases it, so both syncOnce calls are
      // guaranteed to overlap in time before either completes.
      return gate.future;
    });
    when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async {
      scanCalls++;
      return 0;
    });

    final first = coordinator.syncOnce(syncPath);
    final second = coordinator.syncOnce(syncPath);
    gate.complete(1);
    final results = await Future.wait([first, second]);

    expect(pullCalls, 1);
    expect(scanCalls, 1);
    expect(results[0].pulled, results[1].pulled);
  });

  test('a scan that runs concurrently with a *later* syncOnce call still '
      'waits for the in-flight pull to finish first — the guard reuses the '
      'same in-flight future pattern as PullSyncService.pullOnce, so a scan '
      'can never observe a pull that has started but not yet finished '
      'writing', () async {
    final pullGate = Completer<int>();
    var scanStarted = false;
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) => pullGate.future);
    when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async {
      scanStarted = true;
      return 0;
    });

    final run = coordinator.syncOnce(syncPath);
    // Give the event loop a chance to run anything eager — there should be
    // nothing for the scan to do yet, since pull has not resolved.
    await Future<void>.delayed(Duration.zero);
    expect(scanStarted, isFalse);

    pullGate.complete(0);
    await run;
    expect(scanStarted, isTrue);
  });

  test('syncOnce throws SyncFolderMissingException and runs neither pull '
      'nor scan when the sync folder itself is gone (F3) — pull would '
      'otherwise silently recreate it and the scan that follows would then '
      'see every tracked item as deleted', () async {
    final missingPath = p.join(syncPath, 'does-not-exist');
    when(() => mockPreferences.syncFolderPath).thenReturn(missingPath);

    await expectLater(
      coordinator.syncOnce(missingPath),
      throwsA(isA<SyncFolderMissingException>()),
    );

    verifyNever(() => mockPull.pullOnce(any()));
    verifyNever(() => mockScanner.scanOnce(any()));
  });

  group('endSession (F3, PR #16 review round 1)', () {
    test('only stops syncing — it no longer clears the mirror, device id, '
        'or chosen sync folder. That moved to startSession\'s owner check, '
        'so the same account signing back in keeps its mirror instead of '
        're-uploading every local file as a new version', () async {
      await coordinator.endSession();

      verifyNever(() => mockMirror.clearAll());
      verifyNever(() => mockDeviceIdStorage.clear());
      verifyNever(() => mockPreferences.clearSyncFolderPath());
    });

    test('syncOnce is a no-op after endSession, until startSession '
        're-enables it', () async {
      // Stubbed up front so that, without the session flag, syncOnce would
      // run and the test fails on the assertions below — not on an
      // unstubbed mock.
      when(() => mockPull.pullOnce(any())).thenAnswer((_) async => 1);
      when(() => mockScanner.scanOnce(any())).thenAnswer((_) async => 1);
      when(() => mockPreferences.syncOwnerUserId).thenReturn('user-a');
      await coordinator.endSession();

      final result = await coordinator.syncOnce(syncPath);

      expect(result.pulled, 0);
      expect(result.pushed, 0);
      verifyNever(() => mockPull.pullOnce(any()));
      verifyNever(() => mockScanner.scanOnce(any()));

      await coordinator.startSession('user-a');
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 1);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 1);

      final afterRestart = await coordinator.syncOnce(syncPath);

      expect(afterRestart.pulled, 1);
      expect(afterRestart.pushed, 1);
    });
  });

  group('startSession (F3, PR #16 review round 1)', () {
    test('a different owner than the one stored clears the mirror, device '
        'id, and chosen folder before storing the new owner — this is what '
        'protects the next user no matter how the previous session ended '
        '(logout button, expired refresh token, killed app)', () async {
      when(() => mockPreferences.syncOwnerUserId).thenReturn('user-a');

      await coordinator.startSession('user-b');

      verify(() => mockMirror.clearAll()).called(1);
      verify(() => mockDeviceIdStorage.clear()).called(1);
      verify(() => mockPreferences.clearSyncFolderPath()).called(1);
      verify(() => mockPreferences.setSyncOwnerUserId('user-b')).called(1);
      // The previous owner's backoff entries are keyed by local path, not
      // by user — must not delay user-b's first scan of a path it has
      // never even tried (PR #16 review round 2, finding 8).
      verify(() => mockScanner.resetBackoff()).called(1);
    });

    test('the same owner as the one stored clears nothing — a re-login by '
        'the same account must not wipe its own mirror and re-upload every '
        'local file as a new version', () async {
      when(() => mockPreferences.syncOwnerUserId).thenReturn('user-a');

      await coordinator.startSession('user-a');

      verifyNever(() => mockMirror.clearAll());
      verifyNever(() => mockDeviceIdStorage.clear());
      verifyNever(() => mockPreferences.clearSyncFolderPath());
      verify(() => mockPreferences.setSyncOwnerUserId('user-a')).called(1);
      verifyNever(() => mockScanner.resetBackoff());
    });

    test('no stored owner yet (first ever sync session on this machine) '
        'clears nothing', () async {
      when(() => mockPreferences.syncOwnerUserId).thenReturn(null);

      await coordinator.startSession('user-a');

      verifyNever(() => mockMirror.clearAll());
      verify(() => mockPreferences.setSyncOwnerUserId('user-a')).called(1);
      verifyNever(() => mockScanner.resetBackoff());
    });
  });

  group('resetForNewFolder (test 6)', () {
    test('clears the mirror (rows, cursor, bootstrap state, failed events '
        '— all wiped by the same clearAll call)', () async {
      await coordinator.resetForNewFolder('/new/folder');

      verify(() => mockMirror.clearAll()).called(1);
      // Switching folders keeps the session alive, unlike endSession —
      // device id is not touched by this call. The chosen folder itself IS
      // touched, though — that is the point of the next test below.
      verifyNever(() => mockDeviceIdStorage.clear());
      verifyNever(() => mockPreferences.clearSyncFolderPath());
    });

    test('persists the new path only after the mirror clear has actually '
        'finished, not as a fire-and-forget call made regardless of it '
        '(PR #16 review round 2, finding 3) — saving it outside the lock '
        'left a window where a poll tick queued behind this same mutex '
        'could run against the old path, or the new one before the caller '
        'actually meant it', () async {
      final clearGate = Completer<void>();
      when(() => mockMirror.clearAll()).thenAnswer((_) => clearGate.future);

      final future = coordinator.resetForNewFolder('/new/folder');
      // resetForNewFolder is now mid-clear, held open by clearGate.
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => mockPreferences.setSyncFolderPath(any()));

      clearGate.complete();
      await future;

      verify(() => mockPreferences.setSyncFolderPath('/new/folder')).called(1);
    });
  });

  group('syncOnce path guard (finding 3)', () {
    test('no-ops instead of pulling/scanning when its argument no longer '
        'matches the stored sync folder path — the case a poll tick hits '
        'when it captured the path before it changed underneath it',
        () async {
      when(() => mockPreferences.syncFolderPath).thenReturn('/some/other/path');

      final result = await coordinator.syncOnce(syncPath);

      expect(result.pulled, 0);
      expect(result.pushed, 0);
      verifyNever(() => mockPull.pullOnce(any()));
      verifyNever(() => mockScanner.scanOnce(any()));
    });
  });

  group('syncOnce single-flight dedupe is per-path (PR #16 review round 3, '
      'finding 2)', () {
    test('a syncOnce for a different path gets its own run instead of '
        "joining another path's in-flight future — a stale syncOnce('/a') "
        "queued behind resetForNewFolder('/b') must not swallow "
        "syncOnce('/b') into '/a''s (no-op) future, which would leave "
        'neither folder pulled or scanned', () async {
      const stalePath = '/stale/a';
      // The path AppPreferences reports changes the moment
      // resetForNewFolder's setSyncFolderPath call actually lands — a
      // static stub would not let the two queued syncOnce calls below
      // observe that change the way the real preferences store would.
      var storedPath = stalePath;
      when(() => mockPreferences.syncFolderPath).thenAnswer((_) => storedPath);
      when(() => mockPreferences.setSyncFolderPath(any())).thenAnswer((invocation) async {
        storedPath = invocation.positionalArguments[0] as String;
      });
      final clearGate = Completer<void>();
      when(() => mockMirror.clearAll()).thenAnswer((_) => clearGate.future);
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 1);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 1);

      // resetForNewFolder('/b') grabs the mutex first and blocks mid-clear.
      final resetFuture = coordinator.resetForNewFolder(syncPath);
      // A stale syncOnce('/a') — captured before the switch — queues behind
      // it on the same mutex.
      final staleA = coordinator.syncOnce(stalePath);
      // syncOnce('/b') must get its own future, not '/a''s: with path-blind
      // dedupe this would be identical() to staleA, and pull/scan would
      // never run for either folder.
      final syncB = coordinator.syncOnce(syncPath);

      expect(identical(staleA, syncB), isFalse);

      clearGate.complete();
      final staleResult = await staleA;
      final bResult = await syncB;
      await resetFuture;

      // '/a' ran after the switch, saw the stored path had already moved
      // to '/b', and no-opped instead of pulling/scanning against either
      // folder.
      expect(staleResult.pulled, 0);
      expect(staleResult.pushed, 0);
      // '/b' actually ran, exactly once.
      expect(bResult.pulled, 1);
      expect(bResult.pushed, 1);
      verify(() => mockPull.pullOnce(syncPath)).called(1);
      verify(() => mockScanner.scanOnce(syncPath)).called(1);
      verifyNever(() => mockPull.pullOnce(stalePath));
      verifyNever(() => mockScanner.scanOnce(stalePath));
    });
  });

  group('mutex (test 7)', () {
    test('endSession called while syncOnce is in flight runs only after it '
        'completes', () async {
      final pullGate = Completer<int>();
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) => pullGate.future);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 0);

      final syncFuture = coordinator.syncOnce(syncPath);
      // syncOnce is now mid-pull, held open by pullGate.
      await Future<void>.delayed(Duration.zero);

      final endSessionFuture = coordinator.endSession();
      var endSessionCompleted = false;
      unawaited(endSessionFuture.whenComplete(() => endSessionCompleted = true));

      // endSession must not have run yet — the mutex holds it behind the
      // in-flight syncOnce.
      await Future<void>.delayed(Duration.zero);
      expect(endSessionCompleted, isFalse);

      pullGate.complete(0);
      await syncFuture;
      await endSessionFuture;

      expect(endSessionCompleted, isTrue);
      // Proof endSession actually ran (not just that its Future happened to
      // resolve after syncFuture's): syncOnce is now a no-op, which only
      // holds once _sessionEnded has actually been set.
      final afterEndSession = await coordinator.syncOnce(syncPath);
      expect(afterEndSession.pulled, 0);
      expect(afterEndSession.pushed, 0);
    });
  });

  group('heartbeat', () {
    test('sent after a successful pull, even when it applied zero events — '
        '"last synced" means "successfully reconciled", not "changed '
        'something"', () async {
      when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 0);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 0);
      when(() => mockRemote.heartbeat('device-1')).thenAnswer((_) async {});

      await coordinator.syncOnce(syncPath);

      verify(() => mockRemote.heartbeat('device-1')).called(1);
    });

    // The reason the heartbeat is fire-and-forget rather than awaited: the
    // whole run body holds the coordinator's mutex, and Dio retries a
    // 429/5xx heartbeat honouring `Retry-After` capped at 120s. Awaiting it
    // anywhere inside the run would keep that lock for minutes, hanging
    // endSession() on logout and swallowing the 30s poll ticks. Asserted
    // without a timeout on purpose: a regression makes `runFinished` false
    // at the assert, which fails on the claim rather than by hanging (a
    // test that only "catches" a bug by timing out is not a real check).
    test('the run does not wait for the heartbeat — a heartbeat still in '
        'flight must not hold the coordinator lock', () async {
      final heartbeatGate = Completer<void>();
      when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 1);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 0);
      when(() => mockRemote.heartbeat('device-1')).thenAnswer((_) => heartbeatGate.future);

      var runFinished = false;
      final run = coordinator.syncOnce(syncPath).then((_) => runFinished = true);
      await pumpEventQueue(times: 50);

      expect(
        runFinished,
        isTrue,
        reason: 'syncOnce must complete (and release the mutex) while the '
            'heartbeat is still pending',
      );

      heartbeatGate.complete();
      await run;
    });

    test('not sent when pull throws', () async {
      when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => mockPull.pullOnce(syncPath)).thenThrow(Exception('network error'));

      await expectLater(coordinator.syncOnce(syncPath), throwsA(isA<Exception>()));

      verifyNever(() => mockRemote.heartbeat(any()));
    });

    test('a heartbeat that throws does not abort the run — the scan still '
        'runs and the pull result already applied is not lost', () async {
      when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 3);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 1);
      when(() => mockRemote.heartbeat('device-1')).thenThrow(Exception('server error'));

      final result = await coordinator.syncOnce(syncPath);

      expect(result.pulled, 3);
      expect(result.pushed, 1);
      verify(() => mockScanner.scanOnce(syncPath)).called(1);
    });

    test('a device-id lookup that throws (e.g. secure storage failure) does '
        'not abort the run either — the same best-effort guarantee as a '
        'heartbeat network failure', () async {
      when(() => mockDeviceRegistration.localDeviceId())
          .thenThrow(Exception('secure storage unavailable'));
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 3);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 1);

      final result = await coordinator.syncOnce(syncPath);

      expect(result.pulled, 3);
      expect(result.pushed, 1);
      verifyNever(() => mockRemote.heartbeat(any()));
    });

    test('not sent when no device is registered yet (first-run edge case)', () async {
      when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => null);
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 0);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 0);

      await coordinator.syncOnce(syncPath);

      verifyNever(() => mockRemote.heartbeat(any()));
    });

    test('does not block the scan behind it — the scan runs and finishes '
        'while the heartbeat call is still pending, not only after it '
        'resolves (Codex review: a retried 429/5xx heartbeat, honouring '
        'Retry-After up to 120s, must not delay pushing local changes by '
        'minutes)', () async {
      final heartbeatGate = Completer<void>();
      var scanCalled = false;
      when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 0);
      when(() => mockDeviceRegistration.localDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => mockRemote.heartbeat('device-1')).thenAnswer((_) => heartbeatGate.future);
      when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async {
        scanCalled = true;
        return 0;
      });

      // syncOnce itself still awaits the heartbeat before returning (so
      // callers/tests can rely on it having happened) — it just does not
      // let it block the scan that runs alongside it.
      final future = coordinator.syncOnce(syncPath);

      // Give the event loop several turns to run everything eager, with the
      // heartbeat call still held open by heartbeatGate — a single
      // Duration.zero tick is not always enough here, unlike elsewhere in
      // this file: syncOnce's folder-exists check ahead of this is a real
      // Directory.exists() call against the temp dir, not a mocked one, so
      // pumpEventQueue (several delayed(Duration.zero) turns) rather than
      // just one.
      await pumpEventQueue();
      expect(scanCalled, isTrue);

      heartbeatGate.complete();
      await future;
    });
  });
}
