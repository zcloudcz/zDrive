import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/update/auto_update_io.dart';
import 'package:zdrive_app/core/update/update_manifest.dart';

class MockClient extends Mock implements HttpClient {}

class MockRequest extends Mock implements HttpClientRequest {}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.chunks, {this.statusCode = 200, this.contentLength = -1});
  final List<List<int>> chunks;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late MockClient client;
  late MockRequest request;
  late WindowsUpdateBackend backend;
  late UpdateManifest manifest;
  setUpAll(() => registerFallbackValue(Uri.parse('https://drive.zcloud.cz')));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('zdrive-transport-test-');
    client = MockClient();
    request = MockRequest();
    when(() => client.getUrl(any())).thenAnswer((_) async => request);
    backend = WindowsUpdateBackend(
      root.path,
      '0.2.2',
      'unused',
      httpClient: client,
    );
    manifest = UpdateManifest.parse({
      'schemaVersion': 1,
      'version': '0.2.3',
      'url': 'https://drive.zcloud.cz/downloads/zDrive-0.2.3-windows-x64.zip',
      'sha256': sha256.convert([1, 2, 3]).toString(),
      'sizeBytes': 3,
    });
  });
  tearDown(() async {
    backend.close();
    await root.delete(recursive: true);
  });
  test(
    'Successful streamed download becomes verified payload and descriptor',
    () async {
      when(() => request.close()).thenAnswer(
        (_) async => Response([
          [1],
          [2, 3],
        ], contentLength: 3),
      );
      final progress = <int>[];
      await backend.prepare(manifest, progress.add);
      expect(
        await File('${root.path}/updates/0.2.3/payload.zip').readAsBytes(),
        [1, 2, 3],
      );
      expect(
        await File('${root.path}/updates/0.2.3/payload.zip.part').exists(),
        isFalse,
      );
      final pending = jsonDecode(
        await File('${root.path}/updates/pending.json').readAsString(),
      );
      expect(pending, manifest.toJson());
      expect(progress.last, 3);
      verify(() => request.followRedirects = false).called(1);
      verify(() => client.getUrl(manifest.url)).called(1);
    },
  );
  test(
    'Incorrect hash never publishes ready descriptor or leaves partial file',
    () async {
      when(() => request.close()).thenAnswer(
        (_) async => Response([
          [3, 2, 1],
        ]),
      );
      await expectLater(
        backend.prepare(manifest, (_) {}),
        throwsFormatException,
      );
      expect(await File('${root.path}/updates/pending.json').exists(), isFalse);
      expect(
        await File('${root.path}/updates/0.2.3/payload.zip.part').exists(),
        isFalse,
      );
    },
  );
  test(
    'Oversized body is rejected even without content length header',
    () async {
      when(() => request.close()).thenAnswer(
        (_) async => Response([
          [1, 2],
          [3, 4],
        ]),
      );
      await expectLater(
        backend.prepare(manifest, (_) {}),
        throwsFormatException,
      );
      expect(await File('${root.path}/updates/pending.json').exists(), isFalse);
    },
  );
  test('Redirect is rejected instead of following another origin', () async {
    when(
      () => request.close(),
    ).thenAnswer((_) async => Response([], statusCode: 302));
    await expectLater(backend.fetchManifest(), throwsA(isA<HttpException>()));
    verify(() => request.followRedirects = false).called(1);
    verify(
      () => client.getUrl(
        Uri.parse('https://drive.zcloud.cz/downloads/windows-latest.json'),
      ),
    ).called(1);
  });
  test('Manifest size is bounded before JSON parsing', () async {
    when(
      () => request.close(),
    ).thenAnswer((_) async => Response([List.filled(16385, 32)]));
    await expectLater(backend.fetchManifest(), throwsFormatException);
  });
}
