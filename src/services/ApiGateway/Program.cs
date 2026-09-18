using System.Security.Cryptography;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using ModelContextProtocol.AspNetCore;
using Serilog;
using ZDrive.ApiGateway;
using ZDrive.ApiGateway.Mcp;
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
//
// A rejected request is answered immediately (QueueLimit = 0) rather than
// held in the limiter's internal queue: the previous QueueLimit could hold a
// request for up to the full window (~60s) while Dio's receiveTimeout
// (dio_client.dart) is 15s, so the client gave up first and saw a
// DioException with no response — no status code, so RetryInterceptor could
// not even recognise it as a rate-limit rejection to retry. An immediate 429
// always carries a status code and, via OnRejected below, a Retry-After
// header (the fixed window's length, not the time actually left in it — see
// RateLimiterPartitioning.GetRetryAfterSeconds), which the client honours
// instead of guessing a backoff against a window length it doesn't know.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.OnRejected = (context, _) =>
    {
        var retryAfterSeconds = RateLimiterPartitioning.GetRetryAfterSeconds(context.Lease);
        if (retryAfterSeconds != null)
        {
            context.HttpContext.Response.Headers.RetryAfter = retryAfterSeconds;
        }
        return ValueTask.CompletedTask;
    };

    options.AddPolicy("fixed", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        RateLimiterPartitioning.GetPartitionKey(httpContext.User, httpContext.Connection.RemoteIpAddress?.ToString()),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 100,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        }));

    options.AddPolicy("auth", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        RateLimiterPartitioning.GetPartitionKey(httpContext.User, httpContext.Connection.RemoteIpAddress?.ToString()),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 20,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        }));

    // Chunk PUTs (storage-upload-route, /api/v1/storage/upload/**) get their
    // own budget instead of sharing "fixed": clients (this app and BackupCli)
    // use 4 MiB chunks by convention, so a 1 GB upload is already ~256 of
    // them, and sharing "fixed" meant a transfer in progress could 429 the
    // same user's own file list, thumbnails, etc. 4 MiB is not enforced
    // anywhere server-side, though — StorageController.UploadChunk allows up
    // to 50 MB per request, and Kestrel's own 30 MB default applies first —
    // so 600/min is a budget for the well-behaved chunk size clients
    // actually use, not a bandwidth cap backed by a real per-request limit.
    // A fixed window is used (instead of e.g. a ConcurrencyLimiter) so it
    // keeps producing the same RetryAfter metadata the OnRejected handler
    // above already relies on.
    // Public share-link endpoints (anonymous manifest/chunk downloads): a
    // 1 GB shared file is ~250 chunk requests from one visitor, so this
    // needs its own budget the same way "chunk" does for authenticated
    // uploads. Partitioned the same way "auth" is (GetPartitionKey falls
    // back to caller IP since these requests carry no JWT) — same
    // X-Forwarded-For caveat applies.
    options.AddPolicy("publicShare", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        RateLimiterPartitioning.GetPublicSharePartitionKey(
            httpContext.Request.Headers["X-Forwarded-For"].ToString(),
            httpContext.Connection.RemoteIpAddress?.ToString()),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 300,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        }));

    options.AddPolicy("chunk", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        RateLimiterPartitioning.GetPartitionKey(httpContext.User, httpContext.Connection.RemoteIpAddress?.ToString()),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 600,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        }));
});

// YARP reverse proxy
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

// MCP endpoint (Package C — see docs/superpowers/specs/2026-09-18-share-link-api-mcp-design.md).
// The tools call FileService/StorageService's public share-link REST API
// directly over HTTP, using the same base addresses YARP proxies to, read
// straight from config so a deployed app-setting override
// (ReverseProxy__Clusters__fileCluster__Destinations__fileService__Address)
// is picked up automatically. Not routed through YARP — MapShareLinkMcp below
// maps /mcp and /mcp/s/{token} as endpoints of this app itself.
builder.Services.AddHttpContextAccessor();
builder.Services.Configure<McpOptions>(builder.Configuration.GetSection("Mcp"));
builder.Services.AddSingleton<ShareLinkApiClient>();
builder.Services.AddHttpClient("mcpFileService", client =>
{
    client.BaseAddress = new Uri(GatewayMcp.GetFirstClusterAddress(builder.Configuration, "fileCluster"));
    // The services have no AlwaysOn; a cold instance can take ~50s to answer the first request.
    client.Timeout = TimeSpan.FromSeconds(100);
});
builder.Services.AddHttpClient("mcpStorageService", client =>
{
    client.BaseAddress = new Uri(GatewayMcp.GetFirstClusterAddress(builder.Configuration, "storageCluster"));
    client.Timeout = TimeSpan.FromSeconds(100);
});
builder.Services.AddMcpServer()
    .WithHttpTransport(o => o.SessionMode = HttpServerSessionMode.Stateless)
    .WithTools<ShareLinkTools>();

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
// Trade-off: a flood of well-formed but wrongly-signed bearer tokens now
// pays for RSA signature validation before the limiter can shed it, where
// previously the limiter ran first. Partitioning by user id requires this
// order; there is no rate limiting on unauthenticated request volume as a
// result, only on the responses each partition key produces.
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();
app.MapReverseProxy();
GatewayMcp.MapShareLinkMcp(app);

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
