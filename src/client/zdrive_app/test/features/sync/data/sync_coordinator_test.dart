import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/sync/data/local_change_scanner.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';

class MockPullSyncService extends Mock implements PullSyncService {}

class MockLocalChangeScanner extends Mock implements LocalChangeScanner {}

void main() {
  late MockPullSyncService mockPull;
  late MockLocalChangeScanner mockScanner;
  late SyncCoordinator coordinator;

  setUp(() {
    mockPull = MockPullSyncService();
    mockScanner = MockLocalChangeScanner();
    coordinator = SyncCoordinator(mockPull, mockScanner);
  });

  test('syncOnce pulls, then scans — pull strictly completes before the '
      'scan starts', () async {
    final callOrder = <String>[];
    when(() => mockPull.pullOnce('/local/sync')).thenAnswer((_) async {
      callOrder.add('pull');
      return 3;
    });
    when(() => mockScanner.scanOnce('/local/sync')).thenAnswer((_) async {
      callOrder.add('scan');
      return 2;
    });

    final result = await coordinator.syncOnce('/local/sync');

    expect(callOrder, ['pull', 'scan']);
    expect(result.pulled, 3);
    expect(result.pushed, 2);
  });

  test('two concurrent syncOnce calls run pull and scan exactly once — the '
      'second call awaits the first instead of racing it', () async {
    final gate = Completer<int>();
    var pullCalls = 0;
    var scanCalls = 0;
    when(() => mockPull.pullOnce('/local/sync')).thenAnswer((_) async {
      pullCalls++;
      // Held open until the test releases it, so both syncOnce calls are
      // guaranteed to overlap before either completes.
      return gate.future;
    });
    when(() => mockScanner.scanOnce('/local/sync')).thenAnswer((_) async {
      scanCalls++;
      return 0;
    });

    final first = coordinator.syncOnce('/local/sync');
    final second = coordinator.syncOnce('/local/sync');
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
    when(() => mockPull.pullOnce('/local/sync')).thenAnswer((_) => pullGate.future);
    when(() => mockScanner.scanOnce('/local/sync')).thenAnswer((_) async {
      scanStarted = true;
      return 0;
    });

    final run = coordinator.syncOnce('/local/sync');
    // Give the event loop a chance to run anything eager — there should be
    // nothing for the scan to do yet, since pull has not resolved.
    await Future<void>.delayed(Duration.zero);
    expect(scanStarted, isFalse);

    pullGate.complete(0);
    await run;
    expect(scanStarted, isTrue);
  });
}
