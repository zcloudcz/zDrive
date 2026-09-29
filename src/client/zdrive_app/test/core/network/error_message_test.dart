import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/network/api_envelope.dart';
import 'package:zdrive_app/core/network/error_message.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
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

  for (final error in [
    Exception('Internal server details'),
    const ApiException('database_error', 'relation file_versions is missing'),
    const FormatException('Unexpected internal response body'),
    StateError('Local file C:/private/user/document could not be read'),
  ]) {
    test('${error.runtimeType} hides internal details in both locales', () {
      expect(describeError(error, en), en.errorRequestFailed);
      expect(describeError(error, cs), cs.errorRequestFailed);
    });
  }

  group('describeAuthError', () {
    DioException byPathAndStatus(String path, int statusCode) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response(
        requestOptions: RequestOptions(path: path),
        statusCode: statusCode,
        // The backend's own message may contain the email address the user
        // typed, so it must never leak into the mapped text below.
        data: {
          'success': false,
          'error': {
            'code': 'CONFLICT',
            'message': 'A user with email someone@example.com already exists.',
          },
        },
      ),
      type: DioExceptionType.badResponse,
    );

    final table = <String, (String path, int status, String Function(AppLocalizations) expected)>{
      '/auth/login 404 -> invalid credentials': (
        '/auth/login',
        404,
        (l10n) => l10n.authInvalidCredentials,
      ),
      '/auth/login 401 -> invalid credentials': (
        '/auth/login',
        401,
        (l10n) => l10n.authInvalidCredentials,
      ),
      '/auth/register 409 -> email already registered': (
        '/auth/register',
        409,
        (l10n) => l10n.authEmailAlreadyRegistered,
      ),
      '/auth/entra 409 -> account exists another way': (
        '/auth/entra',
        409,
        (l10n) => l10n.authEntraAccountExists,
      ),
      '/auth/entra 403 -> could not verify': (
        '/auth/entra',
        403,
        (l10n) => l10n.authEntraVerificationFailed,
      ),
      '/auth/entra 404 -> sign-in unavailable': (
        '/auth/entra',
        404,
        (l10n) => l10n.authEntraUnavailable,
      ),
    };

    for (final entry in table.entries) {
      final (path, status, expected) = entry.value;
      test(entry.key, () {
        final error = byPathAndStatus(path, status);
        expect(describeAuthError(error, en), expected(en));
        expect(describeAuthError(error, cs), expected(cs));
      });
    }

    test('429 on any auth endpoint -> too many attempts, regardless of path', () {
      for (final path in ['/auth/login', '/auth/register', '/auth/entra']) {
        expect(
          describeAuthError(byPathAndStatus(path, 429), en),
          en.authTooManyAttempts,
        );
      }
    });

    test('an unmapped status/path combination falls back to describeError', () {
      final error = byPathAndStatus('/auth/login', 500);
      expect(describeAuthError(error, en), describeError(error, en));
    });

    test('a non-DioException falls back to describeError', () {
      final error = Exception('boom');
      expect(describeAuthError(error, en), describeError(error, en));
    });

    test('never leaks the backend envelope message (may contain the email)', () {
      final error = byPathAndStatus('/auth/register', 409);
      expect(
        describeAuthError(error, en),
        isNot(contains('someone@example.com')),
      );
    });
  });

  group('describeAuthError for 2FA', () {
    DioException validation(String path, String field) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 400,
        data: {
          'success': false,
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'One or more validation errors occurred.',
            'validationErrors': {
              field: ['x'],
            },
          },
        },
      ),
    );

    test('wrong code at login -> invalid code', () {
      expect(
        describeAuthError(validation('/auth/login/2fa', 'code'), en),
        en.authTwoFactorInvalidCode,
      );
    });

    test('spent or expired challenge at login -> start over', () {
      expect(
        describeAuthError(validation('/auth/login/2fa', 'challengeToken'), en),
        en.authTwoFactorChallengeExpired,
      );
    });

    test('wrong code when confirming enrollment -> invalid code', () {
      expect(
        describeAuthError(validation('/users/me/2fa/confirm', 'code'), cs),
        cs.authTwoFactorInvalidCode,
      );
    });

    test('disable: wrong password vs wrong code are told apart', () {
      expect(
        describeAuthError(validation('/users/me/2fa/disable', 'password'), en),
        en.twoFactorPasswordInvalid,
      );
      expect(
        describeAuthError(validation('/users/me/2fa/disable', 'code'), en),
        en.authTwoFactorInvalidCode,
      );
    });
  });
}
