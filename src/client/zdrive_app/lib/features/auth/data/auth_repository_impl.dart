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
  Future<User> login({
    required String email,
    required String password,
  }) async {
    final response = await _remoteDataSource.login(
      email: email,
      password: password,
    );
    await _tokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
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
    // Backend returns tokens only; load the profile with the new token.
    return getCurrentUser();
  }

  @override
  Future<User> getCurrentUser() async {
    final dto = await _remoteDataSource.getCurrentUser();
    return User(
      id: dto.id,
      email: dto.email,
      displayName: dto.displayName,
      avatarUrl: dto.avatarUrl,
    );
  }

  @override
  Future<void> logout() async {
    await _tokenStorage.clear();
  }
}
