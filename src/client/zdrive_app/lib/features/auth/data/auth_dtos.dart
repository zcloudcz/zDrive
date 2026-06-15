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

@JsonSerializable()
class UserDto {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;

  const UserDto({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) =>
      _$UserDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UserDtoToJson(this);
}
