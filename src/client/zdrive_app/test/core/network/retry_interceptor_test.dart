import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/dio_client.dart';

/// Replays a fixed script of status codes for every request, in order,
/// so tests can assert exactly how many times RetryInterceptor re-issues
/// a request without hitting the network.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.statusCodes);

  final List<int> statusCodes;
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final statusCode = statusCodes[callCount];
    callCount++;
    return ResponseBody.fromString('', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RetryInterceptor', () {
    late Dio dio;
    late _ScriptedAdapter adapter;

    Dio buildDio(List<int> statusCodes) {
      adapter = _ScriptedAdapter(statusCodes);
      dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(dio: dio, maxRetries: 3));
      return dio;
    }

    test('onError_TooManyRequests_RetriesUntilSuccess', () async {
      buildDio([429, 429, 200]);

      final response = await dio.get<String>(
        '/storage/upload/x/chunk/0',
        options: Options(validateStatus: (code) => code == 200),
      );

      expect(response.statusCode, 200);
      expect(adapter.callCount, 3, reason: 'two 429s, then the successful retry');
    });

    test('onError_ServerError_StillRetries', () async {
      buildDio([503, 200]);

      final response = await dio.get<String>(
        '/storage/upload/x/chunk/0',
        options: Options(validateStatus: (code) => code == 200),
      );

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('onError_TooManyRequests_GivesUpAfterMaxRetries', () async {
      buildDio([429, 429, 429, 429, 429]);

      await expectLater(
        dio.get<String>(
          '/storage/upload/x/chunk/0',
          options: Options(validateStatus: (code) => code == 200),
        ),
        throwsA(isA<DioException>()),
      );
      // Initial attempt + 3 retries = 4 calls, then it gives up.
      expect(adapter.callCount, 4);
    });

    test('onError_ClientError_IsNotRetried', () async {
      buildDio([400]);

      await expectLater(
        dio.get<String>(
          '/storage/upload/x/chunk/0',
          options: Options(validateStatus: (code) => code == 200),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1, reason: '400 is not 429 or >=500, so no retry');
    });
  });
}
