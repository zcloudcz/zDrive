using Microsoft.EntityFrameworkCore;
using Serilog;
using ZDrive.PhotoService.Application;
using ZDrive.PhotoService.Infrastructure;
using ZDrive.PhotoService.Infrastructure.Persistence;
using ZDrive.Shared.Extensions;
using ZDrive.Shared.Middleware;
using ZDrive.Shared.Persistence;
using ZDrive.PhotoService.Api.Middleware;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Service", "PhotoService"));

builder.Services.AddSharedServices();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration, builder.Environment.IsDevelopment());

builder.Services.AddControllers();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "zDrive Photo Service",
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

builder.Services.AddHealthChecks()
    .AddDbContextCheck<PhotoDbContext>("database", tags: ["ready"]);

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

// Apply this service's own pending EF migrations on startup, in every
// environment. MigrateWithBaselineAsync creates the physical database if
// missing, then applies only pending migrations tracked in this context's
// own __EFMigrationsHistory table (scoped to the "photos" schema via
// MigrationsHistoryTable in DependencyInjection.cs) — so it is safe for
// every service to run this against the shared "zdrive" database: each
// context only ever touches its own schema and its own history table.
// Unlike the old EnsureCreated-based workaround this replaced, later
// deploys that add tables/columns apply cleanly instead of silently no-op'ing.
// It also baselines installations left over from that old workaround (tables
// exist, no history row) instead of replaying DDL onto them, and takes a
// per-schema advisory lock so concurrent replicas don't race the same
// migration — see DatabaseMigrationExtensions for both.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
    await db.MigrateWithBaselineAsync("photos");
}

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
