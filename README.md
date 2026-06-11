# zDrive

Cloud storage platform with file sync and photo management. See [CLAUDE.md](CLAUDE.md) for architecture, conventions, and full documentation.

## Quick start

```bash
# Start infrastructure (PostgreSQL, Redis, Azurite, Seq, RabbitMQ)
docker-compose up -d

# Run backend services (each in its own terminal; ports come from launchSettings.json)
dotnet run --project src/services/AuthService/ZDrive.AuthService.Api          # :5101
dotnet run --project src/services/FileService/ZDrive.FileService.Api         # :5102
dotnet run --project src/services/StorageService/ZDrive.StorageService.Api   # :5103
dotnet run --project src/services/SyncService/ZDrive.SyncService.Api         # :5104
dotnet run --project src/services/PhotoService/ZDrive.PhotoService.Api       # :5105
dotnet run --project src/services/NotificationService/ZDrive.NotificationService.Api  # :5106
dotnet run --project src/services/ApiGateway                                 # :5100

# Run Flutter client
cd src/client/zdrive_app
flutter pub get
flutter run
```

No further configuration is needed for local development:

- Connection strings for the Docker Compose infrastructure are in each
  service's `appsettings.json`.
- JWT signing keys are **not** stored in the repository. On first run a
  dev RSA key pair is generated into `~/.zdrive/dev-keys/` and shared by
  all locally running services (see `DevJwtKeyProvider` in `ZDrive.Shared`).
- Production deployments supply secrets via environment variables /
  Azure Key Vault — never commit secrets (CI runs a gitleaks scan).
