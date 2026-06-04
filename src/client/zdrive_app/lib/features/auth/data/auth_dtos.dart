import 'package:json_annotation/json_annotation.dart';

part 'auth_dtos.g.dart';

@JsonSerializable()
class AuthResponseDto {
  final String accessToken;
  final String refreshToken;
  final UserDto user;

  const AuthResponseDto({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
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
