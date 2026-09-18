using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Serilog;
using ZDrive.StorageService.Application;
using ZDrive.StorageService.Infrastructure;
using ZDrive.StorageService.Infrastructure.Persistence;
using ZDrive.Shared.Extensions;
using ZDrive.Shared.Middleware;
using ZDrive.Shared.Persistence;
using ZDrive.StorageService.Api.Middleware;

var builder = WebApplication.CreateBuilder(args);

// Serilog
builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Service", "StorageService"));

// Layers
builder.Services.AddSharedServices();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration, builder.Environment.IsDevelopment());

// Controllers
builder.Services.AddControllers();

// Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "zDrive Storage Service",
        Version = "v1"
    });

    options.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Description = "JWT Authorization header. Example: 'Bearer {token}'",
        Name = "Authorization",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    options.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

// Health checks
builder.Services.AddHealthChecks()
    .AddDbContextCheck<StorageDbContext>("database", tags: ["ready"]);

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

// Public share downloads are fail-closed (see ShareDownloadGrantOptions):
// this is the one place that says so out loud, instead of every anonymous
// request just 404ing with no clue why. Both FileService and StorageService
// must have the SAME key — this service only validates what FileService signs.
var shareGrantOptions = app.Services.GetRequiredService<IOptions<ZDrive.Shared.Auth.ShareDownloadGrantOptions>>().Value;
if (!shareGrantOptions.TryGetKey(out _))
{
    app.Logger.LogInformation(
        "Sharing:DownloadGrantKey is missing or too short — public share downloads are disabled. " +
        "Set the same key on FileService and StorageService to enable them.");
}

// Apply this service's own pending EF migrations on startup, in every
// environment. The "zdrive" database itself must already exist — docker-
// compose, Terraform and Testcontainers all provision it — this helper
// connects straight into it and does not create it. It applies only pending
// migrations tracked in this context's own __EFMigrationsHistory table
// (scoped to the "storage" schema via MigrationsHistoryTable in
// DependencyInjection.cs) — so it is safe for every service to run this
// against the shared "zdrive" database: each context only ever touches its
// own schema and its own history table. Unlike the old EnsureCreated-based
// workaround this replaced, later deploys that add tables/columns apply
// cleanly instead of silently no-op'ing. If a schema has tables left over
// from that old workaround (no history row), it aborts loudly instead of
// guessing at what happened, and it takes a per-schema advisory lock so
// concurrent replicas don't race the same migration — see
// DatabaseMigrationExtensions for both.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<StorageDbContext>();
    await db.MigrateWithBaselineAsync("storage");
}

// Middleware pipeline
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseMiddleware<ExceptionHandlingMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// Health endpoints
app.MapHealthChecks("/health/live", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = _ => false // Liveness: always healthy if the process is running
});

app.MapHealthChecks("/health/ready", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.Run();

// Needed for WebApplicationFactory in integration tests
public partial class Program;
