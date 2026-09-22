class ApiConstants {
  // API Gateway (YARP) — routes /api/v1/{service}/** to each microservice.
  // Deployed builds point at their own gateway; pass it at build time, e.g.
  // flutter build web --dart-define=API_BASE_URL=https://<gateway>/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5100/api/v1',
  );

  // Origin of the Drive web app (GitHub Pages). A share link must open the
  // web UI, not the API — and a desktop/mobile build has no "current origin"
  // to derive that from, so it needs its own build-time default.
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://drive.zcloud.cz',
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

  // The backend API app's App Service plan runs without AlwaysOn (deliberate —
  // the plan is memory-constrained), so it unloads when idle and the first
  // request after that hits a cold start — measured at 48s in production on
  // 2026-09-18. Only the FIRST storage call of an upload/download
  // flow needs this longer budget: it wakes the service, so every call after
  // it hits a warm instance and can keep the normal 15s receiveTimeout.
  //
  // Known cost: a sync run holds the SyncCoordinator mutex for its whole
  // duration, and logout (endSession) waits on that same mutex before it
  // completes. So if a user taps logout while the app is stuck in exactly
  // this cold-start hang — the first storage call of the first transfer
  // after an idle period — logout can now take up to 90s to respond instead
  // of 15s. Accepted: it needs that specific timing to happen at all.
  // ponytail: proper fix is a session-level CancelToken that endSession
  // cancels, so logout interrupts an in-flight cold-start wait instead of
  // waiting it out. Not built — add if this wait is ever reported as real.
  static const Duration storageColdStartTimeout = Duration(seconds: 90);
}
