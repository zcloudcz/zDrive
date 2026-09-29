// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuthResponseDto _$AuthResponseDtoFromJson(Map<String, dynamic> json) =>
    AuthResponseDto(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );

Map<String, dynamic> _$AuthResponseDtoToJson(AuthResponseDto instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
      'expiresAt': instance.expiresAt.toIso8601String(),
    };

LoginResponseDto _$LoginResponseDtoFromJson(Map<String, dynamic> json) =>
    LoginResponseDto(
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      twoFactorRequired: json['twoFactorRequired'] as bool? ?? false,
      challengeToken: json['challengeToken'] as String?,
    );

Map<String, dynamic> _$LoginResponseDtoToJson(LoginResponseDto instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
      'expiresAt': instance.expiresAt?.toIso8601String(),
      'twoFactorRequired': instance.twoFactorRequired,
      'challengeToken': instance.challengeToken,
    };

TwoFactorSetupDto _$TwoFactorSetupDtoFromJson(Map<String, dynamic> json) =>
    TwoFactorSetupDto(
      secret: json['secret'] as String,
      otpAuthUri: json['otpAuthUri'] as String,
    );

Map<String, dynamic> _$TwoFactorSetupDtoToJson(TwoFactorSetupDto instance) =>
    <String, dynamic>{
      'secret': instance.secret,
      'otpAuthUri': instance.otpAuthUri,
    };

UserDto _$UserDtoFromJson(Map<String, dynamic> json) => UserDto(
  id: json['id'] as String,
  email: json['email'] as String,
  displayName: json['displayName'] as String,
  avatarUrl: json['avatarUrl'] as String?,
  twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
  hasPassword: json['hasPassword'] as bool? ?? true,
);

Map<String, dynamic> _$UserDtoToJson(UserDto instance) => <String, dynamic>{
  'id': instance.id,
  'email': instance.email,
  'displayName': instance.displayName,
  'avatarUrl': instance.avatarUrl,
  'twoFactorEnabled': instance.twoFactorEnabled,
  'hasPassword': instance.hasPassword,
};
