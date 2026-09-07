using System.Security.Cryptography;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.IdentityModel.Tokens;
using Serilog;
using Yarp.ReverseProxy.Configuration;
using ZDrive.Shared.Extensions;
using ZDrive.Shared.Middleware;

var builder = WebApplication.CreateBuilder(args);

// Serilog
builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Service", "ApiGateway"));

// Shared services
builder.Services.AddSharedServices();

// JWT validation — public key from configuration; in Development fall back to
// the per-machine dev key pair shared with AuthService (no keys in the repo).
var jwtSection = builder.Configuration.GetSection("Jwt");
var publicKeyPem = jwtSection["RsaPublicKeyPem"];
if (string.IsNullOrWhiteSpace(publicKeyPem))
{
    if (!builder.Environment.IsDevelopment())
    {
        throw new InvalidOperationException(
            "Jwt:RsaPublicKeyPem must be configured outside Development.");
    }

    publicKeyPem = ZDrive.Shared.Auth.DevJwtKeyProvider.GetOrCreateKeyPair().PublicKeyPem;
}

var rsa = RSA.Create();
rsa.ImportFromPem(publicKeyPem);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        // Keep raw JWT claim names ("sub", "tenant_id") — ClaimsHelper reads them directly.
        options.MapInboundClaims = false;

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtSection["Issuer"] ?? "zdrive",
            ValidateAudience = true,
            ValidAudience = jwtSection["Audience"] ?? "zdrive-api",
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new RsaSecurityKey(rsa),
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();

// Rate limiting
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddFixedWindowLimiter("fixed", limiterOptions =>
    {
        limiterOptions.PermitLimit = 100;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        limiterOptions.QueueLimit = 10;
    });

    options.AddFixedWindowLimiter("auth", limiterOptions =>
    {
        limiterOptions.PermitLimit = 20;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        limiterOptions.QueueLimit = 5;
    });
});

// YARP reverse proxy
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

// Health checks. The gateway owns no database, so "ready" means the proxy has
// somewhere to send traffic: every cluster must carry at least one destination
// with a non-empty address. Outside Development those addresses come from the
// environment (Container Apps internal FQDNs); a missing one would otherwise
// start a gateway that 502s every request while reporting itself healthy.
// We deliberately do NOT probe the downstream services from here — one sick
// service must not mark the whole gateway unready and take the rest with it.
builder.Services.AddHealthChecks()
    .AddCheck<ProxyConfigHealthCheck>("proxy-config", tags: ["ready"]);

// CORS
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        var origins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
                      ?? ["http://localhost:3000"];
        policy.WithOrigins(origins)
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

var app = builder.Build();

// Middleware
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapReverseProxy();

// Health endpoints
app.MapHealthChecks("/health/live", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = _ => false
});

app.MapHealthChecks("/health/ready", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.Run();

/// <summary>
/// Readiness check asserting YARP loaded a usable route table: at least one
/// cluster, and every cluster with a destination we could actually forward to.
/// </summary>
internal sealed class ProxyConfigHealthCheck(IProxyConfigProvider configProvider) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var config = configProvider.GetConfig();

        if (config.Clusters.Count == 0)
        {
            return Task.FromResult(HealthCheckResult.Unhealthy(
                "YARP loaded no clusters - check the ReverseProxy configuration."));
        }

        // An empty Destinations dictionary fails this the same way a blank
        // address does: All() over an empty sequence is true.
        var unreachable = config.Clusters
            .Where(cluster => cluster.Destinations is null ||
                              cluster.Destinations.Values.All(d => string.IsNullOrWhiteSpace(d.Address)))
            .Select(cluster => cluster.ClusterId)
            .ToList();

        return Task.FromResult(unreachable.Count == 0
            ? HealthCheckResult.Healthy()
            : HealthCheckResult.Unhealthy(
                $"Clusters without a usable destination address: {string.Join(", ", unreachable)}"));
    }
}
