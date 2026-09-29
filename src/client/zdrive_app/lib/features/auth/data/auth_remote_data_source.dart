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

  Future<TwoFactorSetupDto> setupTwoFactor() async {
    final response = await _dio.post(ApiConstants.twoFactorSetup);
    return TwoFactorSetupDto.fromJson(unwrapMap(response));
  }

  Future<List<String>> confirmTwoFactor(String code) async {
    final response = await _dio.post(
      ApiConstants.twoFactorConfirm,
      data: {'code': code},
    );
    return (unwrapMap(response)['recoveryCodes'] as List).cast<String>();
  }

  Future<void> disableTwoFactor({
    required String password,
    required String code,
  }) async {
    await _dio.post(
      ApiConstants.twoFactorDisable,
      data: {'password': password, 'code': code},
    );
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

  Future<UserDto> getCurrentUser() async {
    final response = await _dio.get(ApiConstants.usersMe);
    return UserDto.fromJson(unwrapMap(response));
  }
}
