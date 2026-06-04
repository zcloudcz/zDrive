FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project files for restore
COPY src/shared/ shared/
COPY src/services/AuthService/ services/AuthService/

# Restore dependencies
RUN dotnet restore services/AuthService/AuthService.csproj

# Build
RUN dotnet publish services/AuthService/AuthService.csproj \
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

ENTRYPOINT ["dotnet", "AuthService.dll"]
