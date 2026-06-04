class ApiConstants {
  static const String baseUrl = 'http://localhost:5000/api/v1';

  // Auth
  static const String authRegister = '/auth/register';
  static const String authLogin = '/auth/login';
  static const String authRefresh = '/auth/refresh';
  static const String usersMe = '/users/me';

  // Files
  static const String files = '/files';
  static const String folders = '/files/folders';
  static const String trash = '/files/trash';
  static const String filesSearch = '/files/search';
  static const String shares = '/files/shares';
  static const String uploads = '/files/uploads';
}
