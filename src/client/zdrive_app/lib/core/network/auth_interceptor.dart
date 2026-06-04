import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../auth/token_storage.dart';
import 'api_constants.dart';

@lazySingleton
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  bool _isRefreshing = false;

  AuthInterceptor(this._tokenStorage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await _tokenStorage.refreshToken;
        if (refreshToken == null) {
          _isRefreshing = false;
          return handler.next(err);
        }

        final dio = Dio(
          BaseOptions(baseUrl: ApiConstants.baseUrl),
        );
        final response = await dio.post(
          ApiConstants.authRefresh,
          data: {'refreshToken': refreshToken},
        );

        final newAccess = response.data['accessToken'] as String;
        final newRefresh = response.data['refreshToken'] as String;
        await _tokenStorage.saveTokens(
          accessToken: newAccess,
          refreshToken: newRefresh,
        );

        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResponse = await dio.fetch(err.requestOptions);
        _isRefreshing = false;
        return handler.resolve(retryResponse);
      } catch (_) {
        _isRefreshing = false;
        await _tokenStorage.clear();
      }
    }
    return handler.next(err);
  }
}
