using Microsoft.Extensions.Options;
using Serilog;
using ZDrive.Api.Middleware;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.StorageService.Infrastructure.Persistence;
using ZDrive.SyncService.Infrastructure.Persistence;
using ZDrive.PhotoService.Infrastructure.Persistence;
using ZDrive.Shared.Extensions;
using ZDrive.Shared.Middleware;
using ZDrive.Shared.Persistence;
// NOTE: no `using ZDrive.*Service.Application;` / `...Infrastructure;` — all five
// AddApplication()/AddInfrastructure() extension methods share the same signature
// across namespaces, so a using would cause a CS0121 ambiguity. Called fully
// qualified below instead.

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Service", "Api"));

builder.Services.AddSharedServices();

// Auth first: its AddInfrastructure is the only one that registers the JWT
// bearer scheme (the other three were stripped — see DependencyInjection.cs
// in each). Order among the rest does not matter.
ZDrive.AuthService.Application.DependencyInjection.AddApplication(builder.Services);
ZDrive.AuthService.Infrastructure.DependencyInjection.AddInfrastructure(builder.Services, builder.Configuration, builder.Environment.IsDevelopment());
ZDrive.FileService.Application.DependencyInjection.AddApplication(builder.Services);
ZDrive.FileService.Infrastructure.DependencyInjection.AddInfrastructure(builder.Services, builder.Configuration, builder.Environment.IsDevelopment());
ZDrive.StorageService.Application.DependencyInjection.AddApplication(builder.Services);
ZDrive.StorageService.Infrastructure.DependencyInjection.AddInfrastructure(builder.Services, builder.Configuration, builder.Environment.IsDevelopment());
ZDrive.SyncService.Application.DependencyInjection.AddApplication(builder.Services);
ZDrive.SyncService.Infrastructure.DependencyInjection.AddInfrastructure(builder.Services, builder.Configuration, builder.Environment.IsDevelopment());
ZDrive.PhotoService.Application.DependencyInjection.AddApplication(builder.Services);
ZDrive.PhotoService.Infrastructure.DependencyInjection.AddInfrastructure(builder.Services, builder.Configuration);

// One validation behavior for all five MediatR assemblies.
builder.Services.AddTransient(typeof(MediatR.IPipelineBehavior<,>), typeof(ZDrive.Shared.Behaviors.ValidationBehavior<,>));

// Controllers live in THIS assembly, so plain AddControllers() finds them —
// no AddApplicationPart needed. JsonStringEnumConverter was FileService-only;
// Auth/Storage/Sync only ever take enums as input (numbers still accepted).
builder.Services.AddControllers()
    .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(
        new System.Text.Json.Serialization.JsonStringEnumConverter()));

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(options =>
    {
        options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
        {
            Title = "zDrive API",
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
}

// Names must be unique per HealthCheckService — "database" four times throws.
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AuthDbContext>("auth-db", tags: ["ready"])
    .AddDbContextCheck<FileDbContext>("files-db", tags: ["ready"])
    .AddDbContextCheck<StorageDbContext>("storage-db", tags: ["ready"])
    .AddDbContextCheck<SyncDbContext>("sync-db", tags: ["ready"])
    .AddDbContextCheck<PhotoDbContext>("photos-db", tags: ["ready"]);

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

// Share-grant key check (today in both File and Storage, same message) — once.
var shareGrantOptions = app.Services.GetRequiredService<IOptions<ZDrive.Shared.Auth.ShareDownloadGrantOptions>>().Value;
if (!shareGrantOptions.TryGetKey(out _))
    app.Logger.LogInformation("Sharing:DownloadGrantKey is missing or too short — public share downloads are disabled.");

// Each context migrates its own schema + own __EFMigrationsHistory (advisory
// lock per schema inside MigrateWithBaselineAsync), so running all five in
// one process against the shared "zdrive" DB is safe. Sequential on purpose.
using (var scope = app.Services.CreateScope())
{
    await scope.ServiceProvider.GetRequiredService<AuthDbContext>().MigrateWithBaselineAsync("auth");
    await scope.ServiceProvider.GetRequiredService<FileDbContext>().MigrateWithBaselineAsync("files");
    await scope.ServiceProvider.GetRequiredService<StorageDbContext>().MigrateWithBaselineAsync("storage");
    await scope.ServiceProvider.GetRequiredService<SyncDbContext>().MigrateWithBaselineAsync("sync");
    await scope.ServiceProvider.GetRequiredService<PhotoDbContext>().MigrateWithBaselineAsync("photos");
}

app.UseMiddleware<CorrelationIdMiddleware>();
app.UseMiddleware<ExceptionHandlingMiddleware>();
if (app.Environment.IsDevelopment()) { app.UseSwagger(); app.UseSwaggerUI(); }
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health/live", new() { Predicate = _ => false });
app.MapHealthChecks("/health/ready", new() { Predicate = c => c.Tags.Contains("ready") });
app.Run();

// Needed for WebApplicationFactory in integration tests
public partial class Program;
