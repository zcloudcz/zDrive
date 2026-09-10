using System.Security.Cryptography;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Serilog;
using ZDrive.ApiGateway;
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

// Rate limiting — partitioned per caller (see RateLimiterPartitioning) rather
// than one global counter: a 1 GB upload is ~256 chunk requests, and a single
// global window meant one large transfer would 429 itself halfway through
// and starve every other user at the same time.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddPolicy("fixed", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        RateLimiterPartitioning.GetPartitionKey(httpContext.User, httpContext.Connection.RemoteIpAddress?.ToString()),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 100,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 10
        }));

    options.AddPolicy("auth", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        RateLimiterPartitioning.GetPartitionKey(httpContext.User, httpContext.Connection.RemoteIpAddress?.ToString()),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 20,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 5
        }));
});

// YARP reverse proxy
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

// Health checks
builder.Services.AddHealthChecks();

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
// Authentication runs before the rate limiter so the partitioner above can
// read the authenticated user's id off HttpContext.User — it would always
// see an empty principal (and fall back to IP) if this ran the other way.
app.UseAuthentication();
app.UseRateLimiter();
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

public partial class Program;
