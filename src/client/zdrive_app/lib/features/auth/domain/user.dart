import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final bool twoFactorEnabled;
  // False for Entra-only accounts, which have no 2FA setup of their own.
  final bool hasPassword;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.twoFactorEnabled = false,
    this.hasPassword = true,
  });

  @override
  List<Object?> get props => [
    id,
    email,
    displayName,
    avatarUrl,
    twoFactorEnabled,
    hasPassword,
  ];
}
