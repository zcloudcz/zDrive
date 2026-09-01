using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;
using Serilog;
using ZDrive.StorageService.Application;
using ZDrive.StorageService.Infrastructure;
using ZDrive.StorageService.Infrastructure.Persistence;
using ZDrive.Shared.Extensions;
using ZDrive.Shared.Middleware;
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

// Create this service's own schema + tables on startup, in every environment.
// There are no EF migrations yet — a migration job will replace this once the
// schema stabilizes; until then a fresh database (dev, test or prod)
// provisions itself this way. All services share one physical "zdrive"
// database with one schema per service (Search Path in the connection
// string), so Database.EnsureCreatedAsync() (a DB-level check: "does the
// database have any tables at all?") must NOT be used here — the first
// service to start would create its schema and every later service would
// see "database already has tables" and skip creating its own schema
// entirely. CreateTablesAsync() only touches this context's own
// tables/schema, so every service safely creates its own. Assumes a single
// replica per service (true for the current compose/deploy setup).
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<StorageDbContext>();
    var creator = (RelationalDatabaseCreator)db.Database.GetService<IRelationalDatabaseCreator>();
    try
    {
        if (!await creator.ExistsAsync())
            await creator.CreateAsync(); // physical "zdrive" database, if it doesn't exist yet
        await creator.CreateTablesAsync(); // only this context's schema + tables
    }
    catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.DuplicateTable
                                     || ex.SqlState == PostgresErrorCodes.DuplicateObject
                                     || ex.SqlState == PostgresErrorCodes.DuplicateSchema
                                     || ex.SqlState == PostgresErrorCodes.DuplicateDatabase)
    {
        // Already created by a previous run, or by another service racing to
        // create the shared "zdrive" database on first boot — idempotent no-op
        // either way.
        Log.Warning("Schema init for {DbContext} skipped, already exists ({SqlState}): {Message}",
            db.GetType().Name, ex.SqlState, ex.MessageText);
        // ponytail: this assumes one duplicate object means the whole schema
        // is up to date. CreateTablesAsync has no migration history, so if
        // this context's model gains a table on a later deploy, the DDL
        // transaction fails on the first pre-existing table, rolls back, and
        // the new table never gets created — the Log.Warning above fires, but
        // nothing else surfaces this. Real fix is EF migrations, which track
        // what's already applied per context.
    }
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
