import 'user.dart';

/// Outcome of a password login: either a session, or — for an account with
/// 2FA — a challenge to complete with [AuthRepository.completeTwoFactorLogin].
sealed class LoginResult {
  const LoginResult();
}

final class LoginSucceeded extends LoginResult {
  final User user;

  const LoginSucceeded(this.user);
}

final class LoginTwoFactorRequired extends LoginResult {
  final String challengeToken;

  const LoginTwoFactorRequired(this.challengeToken);
}

class TwoFactorSetup {
  final String secret;
  final String otpAuthUri;

  const TwoFactorSetup({required this.secret, required this.otpAuthUri});
}

abstract class AuthRepository {
  Future<LoginResult> login({required String email, required String password});
  Future<User> completeTwoFactorLogin({
    required String challengeToken,
    String? code,
    String? recoveryCode,
  });
  Future<User> register({
    required String email,
    required String password,
    required String displayName,
  });
  Future<User> loginWithEntra(String accessToken, {String? entraRefreshToken});
  Future<User> getCurrentUser();
  /// Needs the current password: a stolen session alone must not be able to
  /// bind another authenticator.
  Future<TwoFactorSetup> setupTwoFactor({required String password});

  /// Turns 2FA on; returns the one-time recovery codes. All other sessions are
  /// signed out; the fresh token pair for this device is stored here.
  Future<List<String>> confirmTwoFactor(String code);

  /// Same session rotation as [confirmTwoFactor].
  Future<void> disableTwoFactor({
    required String password,
    required String code,
  });
  Future<void> logout();
}
