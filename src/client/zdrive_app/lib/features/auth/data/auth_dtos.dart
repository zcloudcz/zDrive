import 'package:json_annotation/json_annotation.dart';

part 'auth_dtos.g.dart';

/// Mirrors backend `AuthTokenDto` — tokens only, no user. The user profile is
/// fetched separately via GET /users/me.
@JsonSerializable()
class AuthResponseDto {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  const AuthResponseDto({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AuthResponseDtoToJson(this);
}

/// Mirrors backend `LoginResultDto`: the same token fields as
/// [AuthResponseDto] for a normal login, or — for an account with 2FA —
/// null tokens plus [twoFactorRequired] and a [challengeToken] to complete
/// via `POST /auth/login/2fa`.
@JsonSerializable()
class LoginResponseDto {
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  @JsonKey(defaultValue: false)
  final bool twoFactorRequired;
  final String? challengeToken;

  const LoginResponseDto({
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.twoFactorRequired = false,
    this.challengeToken,
  });

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseDtoFromJson(json);

  Map<String, dynamic> toJson() => _$LoginResponseDtoToJson(this);
}

/// Mirrors backend `TwoFactorSetupDto`.
@JsonSerializable()
class TwoFactorSetupDto {
  final String secret;
  final String otpAuthUri;

  const TwoFactorSetupDto({required this.secret, required this.otpAuthUri});

  factory TwoFactorSetupDto.fromJson(Map<String, dynamic> json) =>
      _$TwoFactorSetupDtoFromJson(json);

  Map<String, dynamic> toJson() => _$TwoFactorSetupDtoToJson(this);
}

@JsonSerializable()
class UserDto {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  @JsonKey(defaultValue: false)
  final bool twoFactorEnabled;
  // False for Entra-only accounts (no local password, no 2FA setup).
  @JsonKey(defaultValue: true)
  final bool hasPassword;

  const UserDto({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.twoFactorEnabled = false,
    this.hasPassword = true,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) =>
      _$UserDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UserDtoToJson(this);
}
