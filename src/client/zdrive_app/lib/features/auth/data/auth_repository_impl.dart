import 'package:injectable/injectable.dart';

import '../../../core/auth/token_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/user.dart';
import 'auth_remote_data_source.dart';

@LazySingleton(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final TokenStorage _tokenStorage;

  AuthRepositoryImpl(this._remoteDataSource, this._tokenStorage);

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _remoteDataSource.login(
      email: email,
      password: password,
    );
    if (response.twoFactorRequired) {
      return LoginTwoFactorRequired(response.challengeToken!);
    }
    return LoginSucceeded(
      await _startPasswordSession(
        response.accessToken!,
        response.refreshToken!,
      ),
    );
  }

  @override
  Future<User> completeTwoFactorLogin({
    required String challengeToken,
    String? code,
    String? recoveryCode,
  }) async {
    final response = await _remoteDataSource.loginTwoFactor(
      challengeToken: challengeToken,
      code: code,
      recoveryCode: recoveryCode,
    );
    return _startPasswordSession(response.accessToken, response.refreshToken);
  }

  Future<User> _startPasswordSession(
    String accessToken,
    String refreshToken,
  ) async {
    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    // Password login never carries an Entra refresh token — drop any stale
    // one a previous Entra sign-in on this device left behind (Opus review
    // of PR #72, finding 1: otherwise a later silent renewal in
    // auth_interceptor.dart would revive that other identity's session
    // under this password-login user).
    await _tokenStorage.clearEntraRefreshToken();
    // Backend returns tokens only; load the profile with the new token.
    return getCurrentUser();
  }

  @override
  Future<User> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _remoteDataSource.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    await _tokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    // See login()'s comment above — same identity-mix-up risk.
    await _tokenStorage.clearEntraRefreshToken();
    // Backend returns tokens only; load the profile with the new token.
    return getCurrentUser();
  }

  @override
  Future<User> loginWithEntra(
    String accessToken, {
    String? entraRefreshToken,
  }) async {
    final response = await _remoteDataSource.entraExchange(
      accessToken: accessToken,
    );
    await _tokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    try {
      // Native only (ADR 0003): stash the Entra refresh token for silent
      // renewal — see auth_interceptor.dart. Web never passes one.
      if (entraRefreshToken != null) {
        await _tokenStorage.saveEntraRefreshToken(entraRefreshToken);
      }
      // Backend returns tokens only; load the profile with the new token.
      return await getCurrentUser();
    } catch (_) {
      // Opus review of PR #72, finding 1: a failure here (e.g. getCurrentUser
      // hits a network error) must not leave a fully-formed session for this
      // Entra identity sitting in storage — the caller sees AuthError and
      // assumes nothing was saved. Without this, a *different* user logging
      // in right after with a password would only overwrite the zDrive
      // tokens, leaving this user's Entra refresh token in place for silent
      // renewal to later revive.
      await _tokenStorage.clear();
      rethrow;
    }
  }

  @override
  Future<User> getCurrentUser() async {
    final dto = await _remoteDataSource.getCurrentUser();
    return User(
      id: dto.id,
      email: dto.email,
      displayName: dto.displayName,
      avatarUrl: dto.avatarUrl,
      twoFactorEnabled: dto.twoFactorEnabled,
      hasPassword: dto.hasPassword,
    );
  }

  @override
  Future<TwoFactorSetup> setupTwoFactor({required String password}) async {
    final dto = await _remoteDataSource.setupTwoFactor(password: password);
    return TwoFactorSetup(secret: dto.secret, otpAuthUri: dto.otpAuthUri);
  }

  @override
  Future<List<String>> confirmTwoFactor(String code) async {
    final result = await _remoteDataSource.confirmTwoFactor(code);
    // The server just revoked every refresh token, including this device's
    // old one — the new pair must replace it or the next refresh logs out.
    await _tokenStorage.saveTokens(
      accessToken: result.tokens.accessToken,
      refreshToken: result.tokens.refreshToken,
    );
    return result.recoveryCodes;
  }

  @override
  Future<void> disableTwoFactor({
    required String password,
    required String code,
  }) async {
    final tokens = await _remoteDataSource.disableTwoFactor(
      password: password,
      code: code,
    );
    await _tokenStorage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  @override
  Future<void> logout() async {
    await _tokenStorage.clear();
  }
}
