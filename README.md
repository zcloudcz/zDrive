# zDrive

Cloud storage platform with file sync and photo management. See [CLAUDE.md](CLAUDE.md) for architecture, conventions, and full documentation.

## Quick start

```bash
# Start infrastructure (PostgreSQL, Redis, Azurite, Seq, RabbitMQ)
docker-compose up -d

# Copy and configure environment
cp .env.example .env

# Run a backend service
dotnet run --project src/services/AuthService

# Run Flutter client
cd src/client/zdrive_app
flutter pub get
flutter run
```
