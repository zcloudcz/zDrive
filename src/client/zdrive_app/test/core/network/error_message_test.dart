import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/error_message.dart';
import 'package:zdrive_app/shared/l10n/app_localizations_cs.dart';
import 'package:zdrive_app/shared/l10n/app_localizations_en.dart';

DioException _withStatus(int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/photos/timeline'),
      response: Response(
        requestOptions: RequestOptions(path: '/photos/timeline'),
        statusCode: statusCode,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  final en = AppLocalizationsEn();
  final cs = AppLocalizationsCs();

  // The whole point of this function: the user saw
  // "DioException [bad response]: This exception was thrown because the
  // response has a status code of 502 and RequestOptions.validateStatus was
  // configured to throw…" in the Photos tab, because PhotoService is not
  // deployed and the gateway proxies to localhost.
  group('describeError never leaks Dio plumbing', () {
    // Parameterised over the whole range rather than just 502: an earlier
    // version mapped only >= 500 and let every 4xx fall through to
    // toString(), which is the same leak with a different status code.
    for (final status in [400, 401, 403, 404, 409, 429, 500, 502, 503]) {
      test('$status renders a human sentence', () {
        final message = describeError(_withStatus(status), en);

        expect(message, isNot(contains('DioException')));
        expect(message, isNot(contains('RequestOptions')));
        expect(message, isNot(contains('validateStatus')));
        expect(message, isNot(contains('$status')));
      });
    }

    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      test('$type renders the offline sentence', () {
        final error = DioException(
          requestOptions: RequestOptions(path: '/files'),
          type: type,
        );

        expect(describeError(error, en), en.errorNoConnection);
      });
    }

    test('a DioException with no response and no recognised type still does not '
        'leak — unknown Dio failures are the easiest case to forget', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/files'),
        type: DioExceptionType.unknown,
      );

      expect(describeError(error, en), isNot(contains('DioException')));
    });
  });

  test('5xx and 4xx are told apart — a server fault is not the user\'s problem, '
      'so it gets the "try again later" wording', () {
    expect(describeError(_withStatus(503), en), en.errorServiceUnavailable);
    expect(describeError(_withStatus(404), en), en.errorRequestFailed);
  });

  test('the text comes from AppLocalizations, not from a hardcoded English '
      'sentence — a Czech user must not be the only one reading English', () {
    expect(describeError(_withStatus(502), cs), cs.errorServiceUnavailable);
    expect(describeError(_withStatus(502), cs), isNot(en.errorServiceUnavailable));
  });

  test('a non-Dio error keeps toString(), matching how the rest of the app '
      'surfaces errors', () {
    expect(describeError(Exception('folder is missing'), en),
        contains('folder is missing'));
  });
}
