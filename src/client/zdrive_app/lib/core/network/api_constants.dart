class ApiConstants {
  // API Gateway (YARP) — routes /api/v1/{service}/** to each microservice.
  // Deployed builds point at their own gateway; pass it at build time, e.g.
  // flutter build web --dart-define=API_BASE_URL=https://<gateway>/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5100/api/v1',
  );

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
