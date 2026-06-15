class ApiConstants {
  // API Gateway (YARP) — routes /api/v1/{service}/** to each microservice.
  static const String baseUrl = 'http://localhost:5100/api/v1';

  // Auth (auth-service)
  static const String authRegister = '/auth/register';
  static const String authLogin = '/auth/login';
  static const String authRefresh = '/auth/refresh';
  static const String usersMe = '/users/me';

  // Files (file-service)
  static const String files = '/files';
  static const String trash = '/files/trash';
  static const String filesSearch = '/files/search';

  // Sharing (file-service; gateway routes /api/v1/shares to the file cluster)
  static const String shares = '/shares';

  // Storage / blob side (storage-service)
  static const String storage = '/storage';
  static const String uploadInit = '/storage/upload/init';
}
