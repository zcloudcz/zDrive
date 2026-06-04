import 'user.dart';

abstract class AuthRepository {
  Future<User> login({required String email, required String password});
  Future<User> register({
    required String email,
    required String password,
    required String displayName,
  });
  Future<User> getCurrentUser();
  Future<void> logout();
}
