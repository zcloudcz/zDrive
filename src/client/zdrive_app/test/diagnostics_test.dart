import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/diagnostics/diagnostics_io.dart';
import 'package:zdrive_app/core/diagnostics/network_diagnostics.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diagnostics-test-');
  });
  tearDown(() async {
    await Diagnostics.shutdown();
    // Isolate shutdown closes its file handle asynchronously on Windows.
    for (var i = 0; i < 20; i++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  test('flush persists queued events without stopping the writer', () async {
    await Diagnostics.initialize(directory: directory.path);
    for (var i = 0; i < 100; i++) {
      Diagnostics.event('flush.before_exit', {'sequence': i});
    }
    await Diagnostics.flush();
    final file = File('${directory.path}/diagnostic-0.jsonl');
    expect(await file.readAsString(), contains('"sequence":99'));
    Diagnostics.event('flush.still_running');
    await Diagnostics.flush();
    expect(await file.readAsString(), contains('flush.still_running'));
  });

  test(
    'concurrent writers retain independent sessions and can both export',
    () async {
      await Diagnostics.initialize(directory: directory.path);
      final path = directory.path;
      final rendezvous = ReceivePort();
      final signal = rendezvous.sendPort;
      final second = Isolate.run(() async {
        await Diagnostics.initialize(directory: path);
        for (var i = 0; i < 80; i++) {
          Diagnostics.event('second.writer', {'sequence': i});
        }
        await Diagnostics.flush();
        final resume = ReceivePort();
        signal.send(resume.sendPort);
        await resume.first;
        resume.close();
        Diagnostics.event('second.recovered');
        final exported = await Diagnostics.exportLogs();
        await Diagnostics.shutdown();
        return exported;
      });
      for (var i = 0; i < 80; i++) {
        Diagnostics.event('first.writer', {'sequence': i});
      }
      await Diagnostics.flush();
      (await rendezvous.first as SendPort).send(null);
      rendezvous.close();
      expect(await second, matches(r'diagnostic-export-[^/\\]+\.log$'));
      Diagnostics.event('first.recovered');
      final exported = await Diagnostics.exportLogs();
      expect(exported, isNotNull);
      final records = const LineSplitter()
          .convert(await File(exported!).readAsString())
          .map((line) => jsonDecode(line) as Map)
          .toList();
      expect(
        records.where((record) => record['event'] == 'first.writer').length,
        greaterThan(0),
      );
      expect(
        records.where((record) => record['event'] == 'second.writer').length,
        greaterThan(0),
      );
      expect(records.map((record) => record['session']).toSet().length, 2);
      expect(
        records.any((record) => record['event'] == 'first.recovered'),
        isTrue,
      );
      expect(
        records.any((record) => record['event'] == 'second.recovered'),
        isTrue,
      );
      final events = records
          .where(
            (record) =>
                record['event'] == 'first.writer' ||
                record['event'] == 'second.writer',
          )
          .length;
      if (events < 160) {
        expect(
          records.any(
            (record) => (record['writerDroppedEvents'] as int? ?? 0) > 0,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'temporary failed append does not prevent export or later writes',
    () async {
      await Diagnostics.initialize(directory: directory.path);
      await Diagnostics.flush();
      final file = File('${directory.path}/diagnostic-0.jsonl');
      final saved = await file.rename('${directory.path}/saved.jsonl');
      final obstruction = await Directory(file.path).create();
      Diagnostics.event('append.unavailable');
      await Diagnostics.flush();
      await obstruction.delete();
      await saved.rename(file.path);
      expect(await Diagnostics.exportLogs(), isNotNull);
      Diagnostics.event('append.recovered');
      await Diagnostics.flush();
      final text = await file.readAsString();
      expect(text, contains('append.recovered'));
      expect(text, contains('writerDroppedEvents'));
    },
  );

  test(
    'startup lock contention recovers after the other writer releases',
    () async {
      final lease = await File(
        '${directory.path}/diagnostic.lock',
      ).open(mode: FileMode.append);
      await lease.lock(FileLock.exclusive);
      try {
        await Diagnostics.initialize(directory: directory.path);
      } finally {
        await lease.unlock();
        await lease.close();
      }
      Diagnostics.event('startup.recovered');
      await Diagnostics.flush();
      final exported = await Diagnostics.exportLogs();
      expect(exported, isNotNull);
      expect(
        await File(exported!).readAsString(),
        contains('startup.recovered'),
      );
    },
  );

  test(
    'export flushes real files and excludes private error and field text',
    () async {
      await Diagnostics.initialize(
        directory: directory.path,
        version: '0.2.3+5',
      );
      Diagnostics.event('sync.delete.started', {
        'count': 2,
        'path': r'C:\Users\secret\family.jpg',
        'token': 'Bearer secret',
      });
      Diagnostics.error(
        'sync.delete.failed',
        StateError('secret password'),
        StackTrace.fromString(
          '#0 f (package:zdrive_app/main.dart:22:3)\n#1 C:\\Users\\secret\\file.dart',
        ),
      );
      final path = await Diagnostics.exportLogs();
      expect(path, isNotNull);
      final text = await File(path!).readAsString();
      expect(text, contains('sync.delete.started'));
      expect(text, contains('StateError'));
      expect(text, contains('package:zdrive_app/main.dart:22:3'));
      expect(text, isNot(contains('secret')));
      for (final line in const LineSplitter().convert(text)) {
        expect(jsonDecode(line), isA<Map>());
      }
    },
  );

  test('rotation preserves recent bounded logs', () async {
    await Diagnostics.initialize(directory: directory.path, maxBytes: 700);
    for (var i = 0; i < 30; i++) {
      Diagnostics.event('rotation.event', {'sequence': i});
    }
    final path = await Diagnostics.exportLogs();
    final text = await File(path!).readAsString();
    expect(text, contains('"sequence":29'));
    expect(text.length, lessThan(2100));
    expect(await Diagnostics.exportLogs(), isNot(path));
    expect(
      directory.listSync().where((file) => file.path.endsWith('.jsonl')).length,
      3,
    );
  });

  test('overlapping exports keep independent immutable snapshots', () async {
    await Diagnostics.initialize(directory: directory.path);
    Diagnostics.event('export.first');
    final first = (await Diagnostics.exportLogs())!;
    final original = await File(first).readAsBytes();
    Diagnostics.event('export.second');
    final second = (await Diagnostics.exportLogs())!;
    expect(second, isNot(first));
    expect(await File(first).readAsBytes(), original);
    expect(await File(first).readAsString(), isNot(contains('export.second')));
    expect(await File(second).readAsString(), contains('export.second'));
  });

  test('background worker detects missing UI heartbeat', () async {
    await Diagnostics.initialize(
      directory: directory.path,
      stallThreshold: const Duration(milliseconds: 100),
    );
    // Deliberately block this isolate; the writer must remain responsive.
    sleep(const Duration(milliseconds: 400));
    final text = await File((await Diagnostics.exportLogs())!).readAsString();
    expect(text, contains('ui.heartbeat_stalled'));
  });

  test('network categories never include host, identifiers or query', () {
    expect(
      diagnosticRoute(
        'https://private.example/api/v1/files/secret?token=secret',
      ),
      'files',
    );
    expect(diagnosticRoute('/private-name?password=secret'), 'other');
  });

  test('new session exports durable records from previous writer', () async {
    await Diagnostics.initialize(directory: directory.path);
    Diagnostics.event('before.forced_exit');
    await Diagnostics.exportLogs();
    await Diagnostics.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await Diagnostics.initialize(directory: directory.path);
    Diagnostics.event('after.restart');
    final text = await File((await Diagnostics.exportLogs())!).readAsString();
    expect(text, contains('before.forced_exit'));
    expect(text, contains('after.restart'));
    final sessions = const LineSplitter()
        .convert(text)
        .map((line) => (jsonDecode(line) as Map)['session'])
        .toSet();
    expect(sessions.length, 2);
  });

  test(
    'real HTTP diagnostics keep method timing and status without secrets',
    () async {
      await Diagnostics.initialize(directory: directory.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 403;
        request.response.write('secret response');
        await request.response.close();
      });
      final dio = Dio()..interceptors.add(NetworkDiagnostics());
      try {
        await expectLater(
          dio.delete(
            'http://127.0.0.1:${server.port}/api/v1/files/private-file?token=secret',
            options: Options(headers: {'Authorization': 'Bearer secret'}),
          ),
          throwsA(isA<DioException>()),
        );
        final text = await File(
          (await Diagnostics.exportLogs())!,
        ).readAsString();
        expect(text, contains('http.start.DELETE.files'));
        expect(text, contains('"status":403'));
        expect(text, contains('durationMs'));
        expect(text, isNot(contains('secret')));
        expect(text, isNot(contains('private-file')));
      } finally {
        dio.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
