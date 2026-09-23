import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import 'auth_dtos.dart';

@lazySingleton
class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  Future<AuthResponseDto> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      ApiConstants.authLogin,
      data: {'email': email, 'password': password},
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

  Future<UserDto> getCurrentUser() async {
    final response = await _dio.get(ApiConstants.usersMe);
    return UserDto.fromJson(unwrapMap(response));
  }
}
