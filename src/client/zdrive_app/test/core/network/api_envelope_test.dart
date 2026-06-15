import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/api_envelope.dart';

void main() {
  Response<dynamic> resp(dynamic body) => Response<dynamic>(
        data: body,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/x'),
      );

  group('unwrapMap', () {
    test('returns inner data object on success', () {
      final r = resp({
        'success': true,
        'data': {'id': '1', 'name': 'a'},
        'error': null,
      });
      expect(unwrapMap(r), {'id': '1', 'name': 'a'});
    });

    test('throws ApiException with code+message on failure', () {
      final r = resp({
        'success': false,
        'data': null,
        'error': {'code': 'not_found', 'message': 'missing'},
      });
      expect(
        () => unwrapMap(r),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'not_found')
            .having((e) => e.message, 'message', 'missing')),
      );
    });
  });

  group('unwrapMapList', () {
    test('returns inner data list on success', () {
      final r = resp({
        'success': true,
        'data': [
          {'id': '1'},
          {'id': '2'},
        ],
        'error': null,
      });
      final list = unwrapMapList(r);
      expect(list, hasLength(2));
      expect(list.first['id'], '1');
    });
  });

  group('ensureSuccess', () {
    test('does not throw on success', () {
      expect(() => ensureSuccess(resp({'success': true, 'data': true})),
          returnsNormally);
    });

    test('throws on failure with default code/message when error absent', () {
      final r = resp({'success': false});
      expect(
        () => ensureSuccess(r),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unknown')),
      );
    });
  });

  test('defensive: non-enveloped body is returned as-is', () {
    final r = resp({'id': '1'}); // no "success" key
    expect(unwrapMap(r), {'id': '1'});
  });
}
