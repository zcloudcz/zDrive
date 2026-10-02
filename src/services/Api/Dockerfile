FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project files for restore
COPY src/services/Directory.Build.props services/
COPY src/shared/ shared/
COPY src/services/AuthService/ services/AuthService/
COPY src/services/FileService/ services/FileService/
COPY src/services/StorageService/ services/StorageService/
COPY src/services/SyncService/ services/SyncService/
COPY src/services/PhotoService/ services/PhotoService/
COPY src/services/Api/ services/Api/

# Restore dependencies
RUN dotnet restore services/Api/ZDrive.Api.csproj

# Build
RUN dotnet publish services/Api/ZDrive.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS runtime
WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

COPY --from=build /app/publish .

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health/live || exit 1

ENTRYPOINT ["dotnet", "ZDrive.Api.dll"]
