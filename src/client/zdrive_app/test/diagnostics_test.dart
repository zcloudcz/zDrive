import 'dart:convert';
import 'dart:io';

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

  test('rotation preserves recent bounded logs and a single export', () async {
    await Diagnostics.initialize(directory: directory.path, maxBytes: 700);
    for (var i = 0; i < 30; i++) {
      Diagnostics.event('rotation.event', {'sequence': i});
    }
    final path = await Diagnostics.exportLogs();
    final text = await File(path!).readAsString();
    expect(text, contains('"sequence":29'));
    expect(text.length, lessThan(2100));
    expect(await Diagnostics.exportLogs(), path);
    expect(
      directory.listSync().where((file) => !file.path.endsWith('.lock')).length,
      4,
    );
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
