/// Whether the Photos tab is shown at all. PhotoService and
/// NotificationService are not part of the deployed MVP — against the live
/// backend, the gateway proxies their routes to a `localhost` port nothing
/// is listening on, so every Photos request 502s. Defaults to `false` (the
/// deployed reality); pass `--dart-define=PHOTOS_ENABLED=true` when running
/// against a docker-compose stack that actually has PhotoService up.
const bool kPhotosEnabled = bool.fromEnvironment('PHOTOS_ENABLED');
