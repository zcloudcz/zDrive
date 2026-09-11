import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/push_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';

class MockPullSyncService extends Mock implements PullSyncService {}

class MockLocalChangeScanner extends Mock implements LocalChangeScanner {}

class MockPushSyncService extends Mock implements PushSyncService {}

void main() {
  late MockPullSyncService mockPull;
  late MockLocalChangeScanner mockScanner;
  late MockPushSyncService mockPush;
  late SyncCoordinator coordinator;
  late Directory tempDir;
  late String syncPath;

  setUp(() {
    mockPull = MockPullSyncService();
    mockScanner = MockLocalChangeScanner();
    mockPush = MockPushSyncService();
    coordinator = SyncCoordinator(mockPull, mockScanner, mockPush);
    // A real, existing directory — syncOnce now checks for that before
    // doing anything else (F3), so a bare string like '/local/sync' that
    // does not exist on the test runner's filesystem would fail every
    // test in this file, not just the one added for that check below.
    tempDir = Directory.systemTemp.createTempSync('sync_coordinator_test_');
    syncPath = tempDir.path;

    // Baseline every test below assumes unless it says otherwise: the
    // scan's own writes drain cleanly and nothing is left queued.
    when(() => mockPush.drainOutbox()).thenAnswer((_) async => 0);
    when(() => mockPush.outboxCount()).thenAnswer((_) async => 0);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('syncOnce pulls, then scans, then drains the outbox — each step '
      'strictly completes before the next starts', () async {
    final callOrder = <String>[];
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async {
      callOrder.add('pull');
      return 3;
    });
    when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async {
      callOrder.add('scan');
      return 2;
    });
    when(() => mockPush.drainOutbox()).thenAnswer((_) async {
      callOrder.add('drain');
      return 2;
    });

    final result = await coordinator.syncOnce(syncPath);

    expect(callOrder, ['pull', 'scan', 'drain']);
    expect(result.pulled, 3);
    expect(result.pushed, 2);
    expect(result.queued, 0);
  });

  test('drainOutbox failure does not throw out of syncOnce — the queue '
      'retries next cycle', () async {
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 0);
    when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 1);
    when(() => mockPush.drainOutbox()).thenThrow(Exception('SyncService unreachable'));
    when(() => mockPush.outboxCount()).thenAnswer((_) async => 4);

    final result = await coordinator.syncOnce(syncPath);

    expect(result.pushed, 1);
    expect(result.queued, 4);
  });

  test('queued reflects what is left in the outbox after the drain', () async {
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async => 0);
    when(() => mockScanner.scanOnce(syncPath)).thenAnswer((_) async => 0);
    when(() => mockPush.drainOutbox()).thenAnswer((_) async => 1);
    when(() => mockPush.outboxCount()).thenAnswer((_) async => 2);

    final result = await coordinator.syncOnce(syncPath);

    expect(result.queued, 2);
  });

  test('two concurrent syncOnce calls run pull and scan exactly once — the '
      'second call awaits the first instead of racing it', () async {
    final gate = Completer<int>();
    var pullCalls = 0;
    var scanCalls = 0;
    when(() => mockPull.pullOnce(syncPath)).thenAnswer((_) async {
      pullCalls++;
      // Held open until the test releases it, so both syncOnce calls are
      // guaranteed to overlap before either completes.
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

    await expectLater(
      coordinator.syncOnce(missingPath),
      throwsA(isA<SyncFolderMissingException>()),
    );

    verifyNever(() => mockPull.pullOnce(any()));
    verifyNever(() => mockScanner.scanOnce(any()));
  });
}
