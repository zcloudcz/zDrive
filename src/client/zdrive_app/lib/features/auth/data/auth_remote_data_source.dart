import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'auth_dtos.dart';

@lazySingleton
class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  Future<LoginResponseDto> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      ApiConstants.authLogin,
      data: {'email': email, 'password': password},
    );
    return LoginResponseDto.fromJson(unwrapMap(response));
  }

  Future<AuthResponseDto> loginTwoFactor({
    required String challengeToken,
    String? code,
    String? recoveryCode,
  }) async {
    final response = await _dio.post(
      ApiConstants.authLoginTwoFactor,
      data: {
        'challengeToken': challengeToken,
        'code': code,
        'recoveryCode': recoveryCode,
      },
    );
    return AuthResponseDto.fromJson(unwrapMap(response));
  }

  Future<AuthResponseDto> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _dio.post(
      ApiConstants.authRegister,
      data: {'email': email, 'password': password, 'displayName': displayName},
    );
    return AuthResponseDto.fromJson(unwrapMap(response));
  }

  Future<AuthResponseDto> entraExchange({required String accessToken}) async {
    final response = await _dio.post(
      ApiConstants.authEntraExchange,
      data: {'accessToken': accessToken},
    );
    return AuthResponseDto.fromJson(unwrapMap(response));
  }

  Future<TwoFactorSetupDto> setupTwoFactor({required String password}) async {
    final response = await _dio.post(
      ApiConstants.twoFactorSetup,
      data: {'password': password},
    );
    return TwoFactorSetupDto.fromJson(unwrapMap(response));
  }

  /// Returns the one-time recovery codes and the fresh token pair — enabling
  /// 2FA signs out every other session, this device included until it stores
  /// these.
  Future<({List<String> recoveryCodes, AuthResponseDto tokens})>
  confirmTwoFactor(String code) async {
    final response = await _dio.post(
      ApiConstants.twoFactorConfirm,
      data: {'code': code},
    );
    final data = unwrapMap(response);
    return (
      recoveryCodes: (data['recoveryCodes'] as List).cast<String>(),
      tokens: AuthResponseDto.fromJson(data),
    );
  }

  Future<AuthResponseDto> disableTwoFactor({
    required String password,
    required String code,
  }) async {
    final response = await _dio.post(
      ApiConstants.twoFactorDisable,
      data: {'password': password, 'code': code},
    );
    return AuthResponseDto.fromJson(unwrapMap(response));
  }

  Future<UserDto> getCurrentUser() async {
    final response = await _dio.get(ApiConstants.usersMe);
    return UserDto.fromJson(unwrapMap(response));
  }
}
