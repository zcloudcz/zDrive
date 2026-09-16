import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/update/auto_update_io.dart';
import 'package:zdrive_app/core/update/update_banner.dart';
import 'package:zdrive_app/core/update/update_controller.dart';
import 'package:zdrive_app/core/update/update_manifest.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

Map<String, Object> manifestJson() => {
  'schemaVersion': 1,
  'version': '0.2.3',
  'url': 'https://drive.zcloud.cz/downloads/zDrive-0.2.3-windows-x64.zip',
  'sha256': sha256.convert([1, 2, 3]).toString(),
  'sizeBytes': 3,
};
UpdateManifest get manifest => UpdateManifest.parse(manifestJson());

class FakeBackend implements UpdateBackend {
  @override
  String currentVersion = '0.2.2';
  UpdateManifest? prepared;
  bool previousError = false;
  bool fail = false;
  bool launchFails = false;
  int requests = 0;
  int launches = 0;
  int quits = 0;
  bool closed = false;
  Completer<void>? gate;
  void Function(int)? progress;
  @override
  Future<UpdateManifest?> readPending() async => prepared;
  @override
  Future<bool> consumePreviousError() async => previousError;
  @override
  Future<UpdateManifest> fetchManifest() async {
    requests++;
    await gate?.future;
    if (fail) throw const SocketException('offline');
    return manifest;
  }

  @override
  Future<void> prepare(UpdateManifest value, void Function(int) onBytes) async {
    progress = onBytes;
    onBytes(1);
    prepared = value;
    onBytes(3);
  }

  @override
  Future<void> launch(UpdateManifest value) async {
    launches++;
    if (launchFails) throw StateError('handoff failed');
  }

  @override
  Future<void> quit() async {
    quits++;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test('Version comparison is numeric and rejects pre-release input', () {
    expect(UpdateManifest.compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(UpdateManifest.compareVersions('1.0.0', '1.0.0'), 0);
    expect(UpdateManifest.compareVersions('0.2.1', '0.2.2'), lessThan(0));
    expect(
      () => UpdateManifest.compareVersions('1.0.0-beta', '1.0.0'),
      throwsFormatException,
    );
  });
  for (final mutation in <String, Object>{
    'url': 'https://evil.example/update.zip',
    'sha256': 'invalid',
    'version': '../../evil',
    'sizeBytes': 0,
    'schemaVersion': 2,
  }.entries) {
    test('Manifest rejects invalid ${mutation.key}', () {
      expect(
        () => UpdateManifest.parse(
          manifestJson()..[mutation.key] = mutation.value,
        ),
        throwsFormatException,
      );
    });
  }
  test('Manifest rejects oversized payload and unexpected URL query', () {
    expect(
      () => UpdateManifest.parse(
        manifestJson()..['sizeBytes'] = UpdateManifest.maxPayloadBytes + 1,
      ),
      throwsFormatException,
    );
    expect(
      () => UpdateManifest.parse(
        manifestJson()..['url'] = '${manifest.url}?redirect=1',
      ),
      throwsFormatException,
    );
  });

  late FakeBackend backend;
  late UpdateController controller;
  var drained = false;
  var resumed = false;
  setUp(() {
    backend = FakeBackend();
    drained = resumed = false;
    controller = UpdateController(
      backend,
      drain: () async {
        drained = true;
      },
      resume: () async {
        resumed = true;
      },
    );
  });
  tearDown(() {
    if (!backend.closed) controller.dispose();
  });

  test(
    'Background check prepares bytes without restarting application',
    () async {
      await controller.check();
      expect(controller.phase, UpdatePhase.ready);
      expect(controller.downloadedBytes, 3);
      expect(backend.launches, 0);
      expect(controller.pending?.version, '0.2.3');
    },
  );
  test('Offline check allows retry and does not apply', () async {
    backend.fail = true;
    await controller.check();
    expect(controller.phase, UpdatePhase.error);
    backend.fail = false;
    await controller.check();
    expect(controller.phase, UpdatePhase.ready);
    expect(backend.quits, 0);
  });
  test('Repeated checks share one active download operation', () async {
    backend.gate = Completer<void>();
    final first = controller.check();
    await controller.check();
    expect(backend.requests, 1);
    backend.gate!.complete();
    await first;
  });
  test('Equal or older feed version never downloads', () async {
    backend.currentVersion = '0.2.3';
    await controller.check();
    expect(controller.pending, isNull);
    expect(controller.phase, UpdatePhase.idle);
    backend.currentVersion = '0.3.0';
    await controller.check();
    expect(backend.prepared, isNull);
  });
  test(
    'Startup applies prepared update before auth without draining uninitialized sync',
    () async {
      backend.prepared = manifest;
      expect(await controller.initialize(), isTrue);
      expect(drained, isFalse);
      expect(backend.quits, 1);
    },
  );
  test('Failed helper restart flag prevents startup update loop', () async {
    backend.prepared = manifest;
    expect(await controller.initialize(skipApply: true), isFalse);
    expect(backend.launches, 0);
    expect(controller.phase, UpdatePhase.ready);
  });
  test(
    'Previous helper error remains visible and does not autoapply',
    () async {
      backend.previousError = true;
      backend.prepared = manifest;
      await controller.initialize();
      expect(controller.phase, UpdatePhase.error);
      expect(backend.launches, 0);
    },
  );
  test(
    'Explicit restart drains transfers before helper and actual quit',
    () async {
      final gate = Completer<void>();
      controller.dispose();
      backend = FakeBackend();
      controller = UpdateController(
        backend,
        drain: () => gate.future,
        resume: () async {},
      );
      await controller.check();
      final restart = controller.apply();
      await Future<void>.delayed(Duration.zero);
      expect(backend.launches, 0);
      expect(backend.quits, 0);
      gate.complete();
      expect(await restart, isTrue);
      expect(backend.quits, 1);
    },
  );
  test('Failed helper handoff resumes sync and never quits', () async {
    await controller.check();
    backend.launchFails = true;
    expect(await controller.apply(), isFalse);
    expect(drained, isTrue);
    expect(resumed, isTrue);
    expect(backend.quits, 0);
    expect(controller.phase, UpdatePhase.error);
  });
  test(
    'Disposed controller ignores stale network and progress callbacks',
    () async {
      backend.gate = Completer<void>();
      final operation = controller.check();
      controller.dispose();
      backend.gate!.complete();
      await operation;
      expect(backend.prepared, isNull);
      expect(backend.closed, isTrue);
    },
  );

  test('Pending payload validates size/hash outside UI isolate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zdrive-update-test-',
    );
    final io = WindowsUpdateBackend(directory.path, '0.2.2', 'unused');
    try {
      final update = Directory('${directory.path}/updates/0.2.3');
      await update.create(recursive: true);
      final file = File('${update.path}/payload.zip');
      await file.writeAsBytes([1, 2, 3]);
      final descriptor = File('${directory.path}/updates/pending.json');
      await descriptor.writeAsString(jsonEncode(manifestJson()));
      expect((await io.readPending())?.version, '0.2.3');
      await file.writeAsBytes([3, 2, 1]);
      await expectLater(io.readPending(), throwsFormatException);
      expect(await descriptor.exists(), isFalse);
    } finally {
      io.close();
      await directory.delete(recursive: true);
    }
  });

  testWidgets(
    'Ready banner shows version, restart action and preserves application',
    (tester) async {
      await controller.check();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UpdateBanner(
            controller: controller,
            child: const Scaffold(body: Text('Files remain usable')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('0.2.3'), findsOneWidget);
      expect(find.text('Restart and update'), findsOneWidget);
      expect(find.text('Files remain usable'), findsOneWidget);
      await tester.tap(find.text('Restart and update'));
      await tester.pump();
      await tester.pump();
      expect(backend.quits, 1);
    },
  );
}
