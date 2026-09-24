import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class TokenStorage {
  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _entraRefreshTokenKey = 'entra_refresh_token';

  TokenStorage() : _storage = const FlutterSecureStorage();

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  /// Native only (ADR 0003) — the Entra refresh token used for silent
  /// renewal when the zDrive refresh token hits its 24h absolute cap. Web
  /// never writes this (no secure storage in a browser).
  Future<String?> get entraRefreshToken =>
      _storage.read(key: _entraRefreshTokenKey);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> saveEntraRefreshToken(String token) =>
      _storage.write(key: _entraRefreshTokenKey, value: token);

  /// Drops a stale Entra refresh token without touching the zDrive
  /// access/refresh tokens — used by password login/register (Opus review
  /// of PR #72, finding 1): a device that previously signed in via Entra
  /// and then switches to a *different* user's password must not leave the
  /// old user's Entra refresh token behind, or a later silent renewal
  /// (auth_interceptor.dart) would revive the previous user's session
  /// under the new user's login.
  Future<void> clearEntraRefreshToken() =>
      _storage.delete(key: _entraRefreshTokenKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    // Every path that ends a session (logout, a failed session check, a
    // failed silent renewal) must also drop the Entra refresh token — ADR
    // 0003 requires it cleared on logout and on failure, and this is the
    // one place all of those already route through.
    await _storage.delete(key: _entraRefreshTokenKey);
  }

  Future<bool> get hasTokens async => await accessToken != null;
}
