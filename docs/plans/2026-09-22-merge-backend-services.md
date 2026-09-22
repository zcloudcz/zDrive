# Plán: sloučení AuthService + FileService + StorageService + SyncService do jednoho procesu

Datum: 2026-09-22. Motivace: 5 App Services na sdíleném B2 plánu (`asp-fakvio-b1`,
RG `invoiceapi`) žerou ~1 GB RAM dohromady; 4 z nich jsou tenké ASP.NET hosty nad
stejnou DB a stejným JWT klíčem. Cíl: **jeden proces `ZDrive.Api`** (Auth + File +
Storage + Sync), ApiGateway zůstává samostatný. Navíc: Swagger jen v Development,
`PublishReadyToRun` přes `Directory.Build.props`.

Mimo scope (rozhodnuto, nesahat): GC tuning, `InvariantGlobalization`, migrace na
Container Apps, PhotoService a NotificationService (zůstávají samostatné, nenasazené),
jakékoli změny Azure zdrojů (sekce 10 je pro člověka, ne pro agenta).

Ověřeno čtením kódu (ne odhadem) — viz „Zjištění" u každé sekce.

---

## 0. Zjištění, která plán řídí

| Co | Stav v repu | Důsledek pro merge |
|---|---|---|
| `Program.cs` ×4 | Prakticky identické: Serilog, `AddSharedServices()`, `AddApplication()`, `AddInfrastructure(cfg, isDev)`, Swagger, `AddDbContextCheck<T>("database")`, CORS, `MigrateWithBaselineAsync("<schema>")`, middleware pipeline, `/health/live`+`/health/ready`. FileService navíc `AddJsonOptions(JsonStringEnumConverter)` a File+Storage logují chybějící `Sharing:DownloadGrantKey`. | Jeden Program.cs, 4× volání layer-DI. |
| `AddApplication()` ×4 | Stejný název extension metody ve 4 namespacech (`ZDrive.{X}Service.Application.DependencyInjection`). Každé registruje MediatR z vlastní assembly, validátory a **vlastní** `ValidationBehavior<,>` (4 různé generické typy, 4 namespacy — potvrzeno; obsah souborů je identický). | `using` všech 4 namespaců = CS0121 ambiguita → volat plně kvalifikovaně. 4 behaviory = 4× validace každého requestu (funkčně správně, jen zbytečná práce) → přesunout 1 kopii do `ZDrive.Shared`. |
| `AddInfrastructure()` ×4 | Každá volá `services.AddAuthentication(...).AddJwtBearer(...)` + `AddAuthorization()`. Auth navíc `Configure<JwtSettings>`, `IJwtTokenGenerator`, Argon2, Entra. File+Storage obě `Configure<ShareDownloadGrantOptions>` (stejná sekce `Sharing`). Storage registruje `BlobServiceClient` + `ExpiredUploadSessionSweeper` (hosted service, 1 min initial delay). | **4× `AddJwtBearer("Bearer")` = runtime `InvalidOperationException: Scheme already exists: Bearer`** — blokující, musí se odstranit z 3 Infrastructure projektů. `AddAuthorization`/`AddHttpContextAccessor` jsou TryAdd → OK. `Configure<ShareDownloadGrantOptions>` 2× bindne totéž → neškodné, nechat. |
| `ExceptionHandlingMiddleware` ×4 | FileService verze je **nadmnožina** ostatních (Validation/NotFound/Conflict/Forbidden + QuotaExceeded + TooManyRequests + `DbUpdateException` na `FileNodeConfiguration.NameUniqueIndexName`). Storage má Quota, Auth/Sync jen základ. | Ponechat pouze FileService variantu (přejmenovaný namespace). Unique-index větev je bezpečná i pro ostatní kontexty (matchuje jen konkrétní constraint name). |
| Routy controllerů | Auth: `api/v1/auth`, `api/v1/users`. File: `api/v1/files`, `api/v1/shares`. Storage: `api/v1/storage`, `api/v1/storage/shared`. Sync: `api/v1/sync`. | **Žádná kolize** (sekce 3). |
| appsettings.json | ConnectionStrings klíče `AuthDb`/`FileDb`/`StorageDb`/`SyncDb` (stejný server, různý `Search Path`). `Cors:AllowedOrigins`: Auth/File/Storage `[3000, 5173]`, Sync jen `[3000]`. `Jwt` sekce jen v Sync (Issuer/Audience) + v Development všech (kód má fallback `"zdrive"`/`"zdrive-api"`). File: `Versioning`, `Storage`, `Sharing`. Storage: `Sharing`. Auth: `Entra`. Storage Dev: `ConnectionStrings:AzureBlobStorage`. | Sloučit do jednoho souboru — sjednocení `Cors` na superset, `Jwt` jednou. |
| Health checks | 4× `AddDbContextCheck<T>("database", tags: ["ready"])`. | **Duplicitní název `database` = `HealthCheckService` vyhodí „Duplicate health checks were registered"** → přejmenovat na `auth-db`, `files-db`, `storage-db`, `sync-db`. |
| `public partial class Program` | Každý Api projekt má vlastní globální `Program`. `ZDrive.BackupCli.Tests` kvůli tomu používá `extern alias FileApi/StorageApi` a 3 factory + 3 Postgres kontejnery + fake gateway handler routující podle prefixu. | Po merge 1 `Program` → aliasy pryč, BackupCli env se **zjednoduší** na 1 factory + 1 Postgres. |
| Testovací factory (Auth/File/Storage/Sync) | Každá = `WebApplicationFactory<Program>` + 1 `PostgreSqlContainer`, přesměruje **jen svůj** DbContext (Auth/Storage/Sync přes remove+`AddDbContext`, File přes `ConnectionStrings:FileDb` v konfiguraci) a v `InitializeAsync` migruje jen svůj context. Storage má navíc Azurite kontejner. `AuthService.Tests` má 2 factory (`AuthServiceFactory`, `EntraEnabledFactory`) + `MigrationBaselineTests` (bez hosta). | Sloučený Program.cs při startu migruje **všechny 4** contexty → každá factory musí přesměrovat všechny 4 connection stringy do svého kontejneru (4 schémata v 1 DB), jinak startup padne na `localhost:5432`. |
| Swagger | `AddEndpointsApiExplorer`+`AddSwaggerGen` bezpodmínečně, `UseSwagger/UI` pod `IsDevelopment()` — stejné ve všech 4 i v Photo/Notification. ApiGateway Swagger nemá. | Zabalit i `AddSwaggerGen` do `IsDevelopment()` v merged hostu; Photo/Notification mají stejný vzor → stejná 1řádková změna (levné, nenasazené, bez rizika). |
| `Directory.Build.props` | Neexistuje. Žádný csproj nenastavuje `PublishReadyToRun`. `ZDrive.BackupCli` má `InvariantGlobalization=true` (nechat). Workflows `dotnet publish` nevolají; Dockerfily volají `dotnet publish` **bez `-r`**. | `PublishReadyToRun=true` bez RID = chyba NETSDK1094 → podmínit na `'$(RuntimeIdentifier)' != ''`. Umístit do `src/services/` (ne do rootu — root by chytil i Flutter Windows vcxproj a BackupCli). |
| Gateway | `appsettings.json` clustery `authCluster`(5101)/`fileCluster`(5102)/`storageCluster`(5103)/`syncCluster`(5104) + `photoCluster`/`notificationCluster`. MCP (`GatewayMcp.GetFirstClusterAddress(cfg,"fileCluster"/"storageCluster")`) čte adresy z clusterů. `GatewayRoutingTests` asserťují `ClusterId` pro `sharesLinkRoute`→`fileCluster`, `storageSharedRoute`→`storageCluster`, a že každá routa ukazuje na existující cluster. `docker-compose.prod.yml` override adres 4 clusterů env proměnnými. | Nový cluster `apiCluster` → 1 destinace; 3 zmínky v kódu/testech opravit. |
| Klient (Flutter) | Volá jen gateway (`API_BASE_URL`), nikde přímé porty služeb. Sync enumy posílá jako čísla (`platform: int`), `DeviceDto.Platform` je už `string`. Auth `UserDto.Role` je `string`. | Globální `JsonStringEnumConverter` (dnes jen FileService) je pro Auth/Storage/Sync bezpečný — vstup přijímá čísla i řetězce, výstupní DTO enumy nemají. Žádná změna klienta. |
| Docs/infra odkazující na 4 služby | `README.md` (porty), `CLAUDE.md` (struktura, Build & run, tabulka služeb), `docker-compose.prod.yml`, `.github/workflows/deploy-test.yml` (Container Apps matrix + Dockerfily), `infra/helm`, `infra/terraform/container-apps`, `docs/releases/0.2.0.md` (historický záznam — nesahat). | Kód/compose/README/CLAUDE.md aktualizovat; helm/terraform nechat (nejsou produkční cesta, viz sekce 9). |

---

## 1. Layout nového projektu

Název: **`ZDrive.Api`**, umístění **`src/services/Api/`** — stejný „plochý" vzor jako
`src/services/ApiGateway/ZDrive.ApiGateway.csproj` (csproj + `Program.cs` + `Dockerfile`
přímo ve složce služby, bez Domain/Application/Infrastructure podprojektů — ty zůstávají
tam, kde jsou).

```
src/services/Api/
├── ZDrive.Api.csproj
├── Program.cs
├── appsettings.json
├── appsettings.Development.json
├── Properties/launchSettings.json        # port 5101 (viz sekce 5)
├── Dockerfile
├── Middleware/ExceptionHandlingMiddleware.cs   # = dnešní FileService varianta
└── Controllers/
    ├── Auth/AuthController.cs, UsersController.cs
    ├── Files/FilesController.cs, SharesController.cs
    ├── Storage/StorageController.cs, SharedStorageController.cs
    └── Sync/SyncController.cs            # včetně request recordů, které v něm dnes jsou
```

Namespacy controllerů: `ZDrive.Api.Controllers.{Auth|Files|Storage|Sync}`; middleware
`ZDrive.Api.Middleware`. Obsah controllerů se **nemění** (jen `namespace` řádek + případné
`using` na Application/Infrastructure zůstávají).

`ZDrive.Api.csproj` (vzor = dnešní `ZDrive.FileService.Api.csproj`):

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <RootNamespace>ZDrive.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Serilog.AspNetCore" Version="8.0.3" />
    <PackageReference Include="Serilog.Sinks.Seq" Version="8.0.0" />
    <PackageReference Include="Swashbuckle.AspNetCore" Version="6.9.0" />
    <PackageReference Include="Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore" Version="8.0.11" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="8.0.11">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\AuthService\ZDrive.AuthService.Application\ZDrive.AuthService.Application.csproj" />
    <ProjectReference Include="..\AuthService\ZDrive.AuthService.Infrastructure\ZDrive.AuthService.Infrastructure.csproj" />
    <ProjectReference Include="..\FileService\ZDrive.FileService.Application\ZDrive.FileService.Application.csproj" />
    <ProjectReference Include="..\FileService\ZDrive.FileService.Infrastructure\ZDrive.FileService.Infrastructure.csproj" />
    <ProjectReference Include="..\StorageService\ZDrive.StorageService.Application\ZDrive.StorageService.Application.csproj" />
    <ProjectReference Include="..\StorageService\ZDrive.StorageService.Infrastructure\ZDrive.StorageService.Infrastructure.csproj" />
    <ProjectReference Include="..\SyncService\ZDrive.SyncService.Application\ZDrive.SyncService.Application.csproj" />
    <ProjectReference Include="..\SyncService\ZDrive.SyncService.Infrastructure\ZDrive.SyncService.Infrastructure.csproj" />
    <ProjectReference Include="..\..\shared\ZDrive.Shared\ZDrive.Shared.csproj" />
  </ItemGroup>
</Project>
```

(Domain projekty přijdou tranzitivně přes Application.) `EntityFrameworkCore.Design` je
nutný, protože `dotnet ef migrations add --project <Infrastructure> --startup-project
src/services/Api` teď bude jediný startup projekt pro všechny 4 kontexty — do CLAUDE.md
zapsat příklad příkazu.

**Smazat** (celé složky): `src/services/AuthService/ZDrive.AuthService.Api/`,
`src/services/FileService/ZDrive.FileService.Api/`,
`src/services/StorageService/ZDrive.StorageService.Api/`,
`src/services/SyncService/ZDrive.SyncService.Api/` a 4 Dockerfily
`src/services/{Auth,File,Storage,Sync}Service/Dockerfile`.

**Zachovat beze změny**: všechny Domain/Application/Infrastructure projekty (kromě
bodů v sekci 2), `ZDrive.Shared`, ApiGateway, Photo/Notification, 4 testovací projekty
(upravené dle sekce 6), `ZDrive.BackupCli`.

**`zDrive.sln`**: odebrat 4 `ZDrive.*Service.Api` projekty (GUIDy `B0000005…`,
`C0000004…`, `A5191724…`, `1604FCB4…` včetně jejich řádků v
`ProjectConfigurationPlatforms` a `NestedProjects`), přidat `ZDrive.Api` pod
solution folder `services` (`A0000002…`). Nejjednodušší: `dotnet sln zDrive.sln remove
<4 csproj>` + `dotnet sln zDrive.sln add --solution-folder services src/services/Api/ZDrive.Api.csproj`.

---

## 2. Program.cs — strategie sloučení

### 2a. Předběžné úpravy v knihovnách (nutné, ne kosmetika)

1. **JWT jen jednou.** Z `ZDrive.FileService.Infrastructure/DependencyInjection.cs`,
   `ZDrive.StorageService.Infrastructure/DependencyInjection.cs` a
   `ZDrive.SyncService.Infrastructure/DependencyInjection.cs` **odstranit** blok
   „Authentication" (načtení `Jwt:RsaPublicKeyPem`, dev fallback, `RSA.Create`,
   `AddAuthentication().AddJwtBearer()`, `AddAuthorization()`) — zůstane jen v
   `ZDrive.AuthService.Infrastructure` (ta potřebuje i privátní klíč a už dnes
   registruje totéž). Smazat pak nepoužité `using` (`System.Security.Cryptography`,
   `Microsoft.AspNetCore.Authentication.JwtBearer`, `Microsoft.IdentityModel.Tokens`)
   a u File/Sync i `using ZDrive.Shared.Auth`, pokud ho nic jiného nepoužívá
   (File ho používá pro `ShareDownloadGrantOptions`/`DevShareGrantKeyProvider` — nechat).
   Důvod: `AddJwtBearer` se stejným schématem 4× = startup exception (viz Zjištění).
   Balíček `Microsoft.AspNetCore.Authentication.JwtBearer` v těch 3 csproj lze nechat
   (nic nerozbije; odstranit jen pokud tam nic jiného z něj nezůstane).

2. **`ValidationBehavior` jednou.** Přesunout
   `src/services/AuthService/ZDrive.AuthService.Application/Behaviors/ValidationBehavior.cs`
   do `src/shared/ZDrive.Shared/Behaviors/ValidationBehavior.cs` (namespace
   `ZDrive.Shared.Behaviors`), smazat kopie v Auth/File/Storage/Sync Application
   (Photo/Notification **nechat**, nejsou součástí merge). V těch 4 `AddApplication()`
   smazat řádek `services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));`
   a `using ZDrive.{X}.Application.Behaviors;`. `ZDrive.Shared.csproj` musí dostat
   `<PackageReference Include="MediatR" .../>` a `FluentValidation` ve stejných verzích,
   jaké mají Application projekty (opsat z `ZDrive.AuthService.Application.csproj`).
   Registrace pak jednou v Program.cs (bod 2b).

### 2b. Program.cs (pořadí registrací)

```csharp
using Microsoft.Extensions.Options;
using Serilog;
using ZDrive.Api.Middleware;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.StorageService.Infrastructure.Persistence;
using ZDrive.SyncService.Infrastructure.Persistence;
using ZDrive.Shared.Extensions;
using ZDrive.Shared.Middleware;
using ZDrive.Shared.Persistence;
// POZOR: žádné `using ZDrive.*Service.Application;` ani `...Infrastructure;` —
// AddApplication()/AddInfrastructure() mají ve 4 namespacech stejnou signaturu
// a using by způsobil CS0121. Volá se plně kvalifikovaně níže.

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

// One validation behavior for all four MediatR assemblies (was 4 identical copies).
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
    builder.Services.AddSwaggerGen(options => { /* beze změny, Title = "zDrive API" */ });
}

// Names must be unique per HealthCheckService — "database" four times throws.
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AuthDbContext>("auth-db", tags: ["ready"])
    .AddDbContextCheck<FileDbContext>("files-db", tags: ["ready"])
    .AddDbContextCheck<StorageDbContext>("storage-db", tags: ["ready"])
    .AddDbContextCheck<SyncDbContext>("sync-db", tags: ["ready"]);

builder.Services.AddCors(/* beze změny */);

var app = builder.Build();

// Share-grant key check (dnes v File i Storage, stejná hláška) — jednou.
var shareGrantOptions = app.Services.GetRequiredService<IOptions<ZDrive.Shared.Auth.ShareDownloadGrantOptions>>().Value;
if (!shareGrantOptions.TryGetKey(out _))
    app.Logger.LogInformation("Sharing:DownloadGrantKey is missing or too short — public share downloads are disabled.");

// Each context migrates its own schema + own __EFMigrationsHistory (advisory
// lock per schema inside MigrateWithBaselineAsync), so running all four in
// one process against the shared "zdrive" DB is safe. Sequential on purpose.
using (var scope = app.Services.CreateScope())
{
    await scope.ServiceProvider.GetRequiredService<AuthDbContext>().MigrateWithBaselineAsync("auth");
    await scope.ServiceProvider.GetRequiredService<FileDbContext>().MigrateWithBaselineAsync("files");
    await scope.ServiceProvider.GetRequiredService<StorageDbContext>().MigrateWithBaselineAsync("storage");
    await scope.ServiceProvider.GetRequiredService<SyncDbContext>().MigrateWithBaselineAsync("sync");
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

public partial class Program;
```

Poznámky:
- **`AddApplicationPart` není potřeba** — controllery se fyzicky přesouvají do
  `ZDrive.Api`, takže jsou v entry assembly. (Alternativa „nechat 4 Api projekty jako
  class library + `AddApplicationPart`" byla zavržena: ponechává 4 projekty, které
  zadání chce smazat.)
- Dlouhý komentář u migrací z původních Program.cs zkrátit na výše uvedený; detail je
  v `DatabaseMigrationExtensions` a CLAUDE.md.
- `ExpiredUploadSessionSweeper` (Storage) se registruje uvnitř Storage `AddApplication()`
  — beze změny, běží v merged procesu.
- Serilog `Service` property se mění z 4 hodnot na `"Api"` — Seq dotazy filtrující
  `Service = 'FileService'` přestanou matchovat (zmínit v PR description).

---

## 3. Ověření rout — výsledek

Prefixy `[Route]` (všechny absolutní, bez `[controller]` tokenu kromě Auth, kde
`[controller]` = `auth` / `users`):

| Controller | Route |
|---|---|
| AuthController | `api/v1/auth` |
| UsersController | `api/v1/users` |
| FilesController | `api/v1/files` |
| SharesController | `api/v1/shares` |
| StorageController | `api/v1/storage` |
| SharedStorageController | `api/v1/storage/shared` |
| SyncController | `api/v1/sync` |

**Kolize: žádná.** `storage` vs `storage/shared` už dnes koexistují v jednom procesu
(StorageService). Health endpointy `/health/live|ready` se mapují jednou. Žádný
controller nemá `[Route("")]` ani conventional routing. Plán není blokován.

Ověřovací krok pro agenta po přesunu: `dotnet run --project src/services/Api` a
`GET /swagger/v1/swagger.json` (Development) musí obsahovat všech 7 prefixů; ASP.NET
při ambiguitě rout vyhodí `AmbiguousMatchException` až za běhu na konkrétní request,
takže navíc spustit integrační testy (sekce 6), které pokrývají všechny prefixy.

---

## 4. Sloučení konfigurace

`src/services/Api/appsettings.json`:

```json
{
  "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning", "Microsoft.EntityFrameworkCore": "Warning" } },
  "Serilog": {
    "Using": [ "Serilog.Sinks.Console", "Serilog.Sinks.Seq" ],
    "MinimumLevel": { "Default": "Information", "Override": { "Microsoft.AspNetCore": "Warning", "Microsoft.EntityFrameworkCore": "Warning" } },
    "WriteTo": [ { "Name": "Console" } ],
    "Enrich": [ "FromLogContext" ]
  },
  "ConnectionStrings": {
    "AuthDb":    "Host=localhost;Port=5432;Database=zdrive;Username=zdrive;Password=zdrive_dev;Search Path=auth",
    "FileDb":    "Host=localhost;Port=5432;Database=zdrive;Username=zdrive;Password=zdrive_dev;Search Path=files",
    "StorageDb": "Host=localhost;Port=5432;Database=zdrive;Username=zdrive;Password=zdrive_dev;Search Path=storage",
    "SyncDb":    "Host=localhost;Port=5432;Database=zdrive;Username=zdrive;Password=zdrive_dev;Search Path=sync"
  },
  "Jwt": { "Issuer": "zdrive", "Audience": "zdrive-api" },
  "Versioning": { "MaxVersionsPerFile": 10 },
  "Storage": { "DefaultUserQuotaBytes": 53687091200 },
  "Sharing": { "DownloadGrantKey": "" },
  "Entra": { "Enabled": false, "TenantId": "", "Audience": "", "RequiredScope": "" },
  "Cors": { "AllowedOrigins": [ "http://localhost:3000", "http://localhost:5173" ] },
  "AllowedHosts": "*"
}
```

- 4 ConnectionStrings klíče **zůstávají odděleně** (každý Infrastructure čte svůj,
  `Search Path` se liší). V Azure to znamená 4 app settings
  `ConnectionStrings__AuthDb` … místo 1 na každé app — hodnoty jsou dnes stejné až na
  `Search Path` (sekce 10).
- `Jwt`: jednou (Sync ho měl v appsettings.json, ostatní jen v Development; kód má
  fallback na stejné hodnoty). `Jwt:RsaPrivateKeyPem`/`RsaPublicKeyPem` přichází z env
  jako dnes u Auth — nově musí být **privátní** klíč na merged app (dřív jen zdrive-auth).
- `Cors`: superset (Sync měl jen `:3000`) — rozšíření, ne zúžení.
- `Sharing:DownloadGrantKey`: jednou; File i Storage teď čtou tutéž hodnotu z definice
  → odpadá riziko rozjetých klíčů, o kterém mluví komentář v Program.cs.

`appsettings.Development.json`: sloučit File+Storage+Auth varianty
(Debug logging, Seq sink, `Jwt` s `AccessTokenExpirationMinutes: 15` a
`RefreshTokenExpirationDays: 30`, `ConnectionStrings:AzureBlobStorage:
"UseDevelopmentStorage=true"`, `Sharing`). Sync Dev soubor nepřidává nic.

---

## 5. ApiGateway

`src/services/ApiGateway/appsettings.json`:
- Clusters: `authCluster`, `fileCluster`, `storageCluster`, `syncCluster` → **jeden
  `apiCluster`** s destinací `apiService`, `Address: http://localhost:5101`
  (merged host přebírá port 5101 = bývalý Auth; 5102–5104 se uvolní). `photoCluster`
  a `notificationCluster` beze změny.
- Routes: u `auth-route`, `users-route`, `files-route`, `sharesLinkRoute`,
  `shares-route`, `storageSharedRoute`, `storage-upload-route`, `storage-route`,
  `sync-route` změnit `"ClusterId"` na `"apiCluster"`. Match/Transforms/RateLimiter/
  AuthorizationPolicy **beze změny** — per-prefix rate limity zůstávají.

Kód: `src/services/ApiGateway/Program.cs` ř. 169 a 175 —
`GatewayMcp.GetFirstClusterAddress(builder.Configuration, "fileCluster")` /
`"storageCluster"` → oba `"apiCluster"` (komentář nad tím zmiňuje
`ReverseProxy__Clusters__fileCluster__...` → přepsat na `apiCluster`).

Testy: `src/services/ApiGateway.Tests/Integration/GatewayRoutingTests.cs` ř. 94–95
`InlineData(..., "fileCluster")` / `"storageCluster"` → `"apiCluster"`. Test
`EveryRoute_PointsAtADefinedCluster` a `ClusterAndDestinationIds_ContainNoHyphens`
projdou samy (`apiCluster`/`apiService` bez pomlček).

Lokální dev:
- `src/services/Api/Properties/launchSettings.json`: profil `Api`,
  `applicationUrl: http://localhost:5101`.
- `README.md` Quick start: 4 řádky `dotnet run` nahradit jedním
  `dotnet run --project src/services/Api   # :5101`.
- `CLAUDE.md`: tabulka služeb (řádky auth/file/storage/sync → poznámka, že běží v jednom
  procesu `ZDrive.Api`), „Repository structure" (přidat `Api/`), „Build & run"
  (příklad `dotnet ef ... --startup-project src/services/Api`).
- `docker-compose.yml` nesahat (spouští jen infrastrukturu).
- `docker-compose.prod.yml`: služby `auth-service`, `file-service`, `storage-service`,
  `sync-service` nahradit jednou `api` (build `src/services/Api/Dockerfile`, env:
  4× `ConnectionStrings__*Db`, `AZURE_STORAGE_CONNECTION_STRING`, `Jwt__*`,
  `env_file: .env, .env.auth-secrets`). V `api-gateway` nahradit 4 řádky
  `ReverseProxy__Clusters__{auth,file,storage,sync}Cluster__...` jedním
  `ReverseProxy__Clusters__apiCluster__Destinations__apiService__Address: http://api:8080`
  a `depends_on` zkrátit.
- `src/services/Api/Dockerfile`: opsat `AuthService/Dockerfile`, `COPY` navíc
  `src/services/{Auth,File,Storage,Sync}Service/` (bez smazaných Api složek),
  restore/publish `services/Api/ZDrive.Api.csproj`, entrypoint `ZDrive.Api.dll`.
- `.github/workflows/deploy-test.yml` (Container Apps, manuální): matrix 7 → 4 položky
  `{gateway, ApiGateway}, {api, Api}, {photo, PhotoService}, {notification,
  NotificationService}` a v hlavičce poznámku, že `CONTAINERAPP_NAMES_JSON` a
  `infra/terraform/container-apps` ještě znají 7 apps — do jejich úpravy workflow
  nepouštět. (Terraform/Helm sám neupravovat — mimo scope, sekce 9.)
- `src/client/zdrive_app/lib/core/network/api_constants.dart` ř. 36–41: komentář
  mluví o „StorageService's App Service" cold startu — přepsat na „the backend API
  app" (chování stejné, AlwaysOn na merged app viz sekce 10). Kód beze změny.

---

## 6. Testy

Doporučení = **nejmenší churn**: 4 testovací projekty **zůstávají** (Auth/File/
Storage/Sync.Tests), každý dál testuje „svou" část přes `WebApplicationFactory<Program>`
— `Program` je teď ten z `ZDrive.Api` (jediný v grafu referencí, aliasy nejsou třeba).
Neslučovat do jednoho projektu: přesun ~100 souborů a společný fixture nepřinese
pokrytí navíc, jen konflikty.

Nutné změny v každém `*.Tests.csproj`: `ProjectReference` na
`..\{X}Service\ZDrive.{X}Service.Api\...csproj` → `..\Api\ZDrive.Api.csproj`.
(`Microsoft.AspNetCore.Mvc.Testing` a Testcontainers balíčky už mají.)

Nutné změny ve factory (blokující — merged host při startu migruje všechny 4 kontexty):
každá factory přesměruje **všechny 4** connection stringy do svého jednoho
Postgres kontejneru (4 schémata v jedné DB `zdrive_test`; `MigrateWithBaselineAsync`
schéma založí). Vzor = dnešní `FileServiceFactory` (konfigurační override, ne
remove+AddDbContext):

```csharp
builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
{
    ["ConnectionStrings:AuthDb"]    = _postgres.GetConnectionString() + ";Search Path=auth",
    ["ConnectionStrings:FileDb"]    = _postgres.GetConnectionString() + ";Search Path=files",
    ["ConnectionStrings:StorageDb"] = _postgres.GetConnectionString() + ";Search Path=storage",
    ["ConnectionStrings:SyncDb"]    = _postgres.GetConnectionString() + ";Search Path=sync",
}));
```

Konkrétně:
- `AuthServiceFactory`, `EntraEnabledFactory`, `SyncServiceFactory`,
  `StorageServiceFactory`: nahradit blok „Remove real DbContext + AddDbContext" tímto
  overridem (u Storage zůstává výměna `BlobServiceClient`/`IBlobStorageService` za
  Azurite). `FileServiceFactory`: doplnit 3 chybějící klíče. Vlastní
  `db.Database.MigrateAsync()` v `InitializeAsync` může zůstat (no-op po startu hosta)
  nebo se smazat — smazat, ať je jasné, kdo migruje.
- Auth/File/Sync factory nemají Azurite: Storage `AddInfrastructure` v Development
  spadne na `UseDevelopmentStorage=true`; `BlobServiceClient` konstruktor se
  nepřipojuje a `ExpiredUploadSessionSweeper` má 1 min initial delay → **Azurite pro
  ně není potřeba**. Ověřit během běhu testů, že v logu není chyba sweeperu (testy
  trvají < 1 min na factory; kdyby ne, sweeper chybu jen zaloguje, host nepadá).
- `MigrationBaselineTests` — bez hosta, beze změny.
- `FileService.Tests/Unit/ExceptionHandlingMiddlewareQuotaTests.cs`:
  `using ZDrive.FileService.Api.Middleware;` → `using ZDrive.Api.Middleware;`.
- `StorageService.Tests/Integration/SharedUploadFlowTests.cs`:
  `using ZDrive.StorageService.Api.Controllers;` → `using ZDrive.Api.Controllers.Storage;`.
- `StorageService.Tests` a `FileService.Tests` `PostConfigure<JwtBearerOptions>("Bearer", …)`
  fungují dál (schéma registruje Auth Infrastructure).

`src/tools/ZDrive.BackupCli.Tests` — **zjednodušení**:
- csproj: 3 `ProjectReference` na Api projekty (vč. `Aliases`) → 1 na `ZDrive.Api`;
  Infrastructure reference nechat (používá `AuthDbContext` atd.). Komentář o aliasech
  smazat.
- `BackupCliEnvironment.cs`: smazat `extern alias`, 3 Postgres kontejnery → 1, 3
  factory → 1 `WebApplicationFactory<Program>` s jedním `ConfigureWebHost`
  (override 4 connection stringů + Azurite výměna jako dnes v `ConfigureStorage`).
  Doc-comment o „jeden kontejner na službu kvůli izolaci" smazat (důvod pominul).
- `BackupCliGatewayHandler.cs`: 3 `HttpClient` → 1; `switch` podle prefixu zrušit —
  vše jde do jednoho klienta (nechat výjimku pro neznámý prefix, ať test dál hlídá
  kontrakt cest — jednořádkový `if (!path.StartsWith("/api/v1/")) throw`).

Testcontainers: každý test fixture dál startuje **1** Postgres (+ Azurite u Storage
a BackupCli). Celkový počet kontejnerů v CI klesá (BackupCli 3→1). Schémata `auth`,
`files`, `storage`, `sync` vznikají v jedné DB — přesně jako v produkci.

Ověření: `dotnet test --filter Category!=Integration` a `dotnet test --filter
Category=Integration` zelené lokálně (Docker) — stejné příkazy používá `backend-ci.yml`.

---

## 7. Swagger

V `src/services/Api/Program.cs` (viz 2b): `AddEndpointsApiExplorer()` +
`AddSwaggerGen(...)` zabalit do `if (builder.Environment.IsDevelopment())`; `UseSwagger/
UseSwaggerUI` už podmíněné jsou. Bez `AddSwaggerGen` mimo Development se negeneruje
ApiExplorer model ani Swashbuckle generátor (úspora paměti byla důvod).

PhotoService a NotificationService mají identický vzor (`AddSwaggerGen` bez podmínky,
`Program.cs` ř. 24–25 resp. 36–37) → stejná jednořádková podmínka. Nejsou nasazené,
takže bez efektu v Azure, ale je to stejné riziko-nula a drží kód konzistentní.
ApiGateway Swagger nemá — nic.

---

## 8. Directory.Build.props

Soubor **`src/services/Directory.Build.props`** (ne root — root by importoval i Flutter
Windows `vcxproj` pod `src/client` a `ZDrive.BackupCli` pod `src/tools`, který
nepublikujeme přes CI a má vlastní `InvariantGlobalization`):

```xml
<Project>
  <PropertyGroup>
    <!-- ReadyToRun needs a RuntimeIdentifier (NETSDK1094 otherwise), so it only
         kicks in for RID-specific publishes — the App Service ZIPs are built with
         `dotnet publish -r linux-x64 --self-contained false`. The Dockerfiles
         publish without a RID and are unaffected. -->
    <PublishReadyToRun Condition="'$(RuntimeIdentifier)' != ''">true</PublishReadyToRun>
  </PropertyGroup>
</Project>
```

- Konflikty: žádný csproj pod `src/services` (`ZDrive.ApiGateway`, `ZDrive.PhotoService.Api`,
  `ZDrive.NotificationService.Api`, nový `ZDrive.Api`, knihovny, testy) `PublishReadyToRun`
  nenastavuje → props platí bez přebití. Testovací projekty se nepublikují → bez vlivu.
- Nepřidávat `PublishTrimmed`, `InvariantGlobalization`, ani centralizaci
  `TargetFramework`/`Nullable` (nebylo zadáno).
- Ověření: `dotnet publish src/services/Api -c Release -r linux-x64 --self-contained false
  -o /tmp/r2r` proběhne a výstupní `ZDrive.Api.dll` je výrazně větší než z buildu
  (R2R obraz); `dotnet publish src/services/Api -c Release` bez `-r` proběhne beze změny.
  Do `docs/releases/`-stylu deploy příkazu pro příští release přidat `-r linux-x64`.

---

## 9. Rollback, rizika, CI

**CI soubory odkazující na staré cesty:**
- `.github/workflows/backend-ci.yml` — používá jen `zDrive.sln` a glob `src/services/**`
  → **bez změny**, nový projekt i smazané projekty pokryje automaticky.
- `.github/workflows/deploy-test.yml` — matrix dirs + Dockerfily (sekce 5). Manuální
  workflow, nezablokuje merge.
- `deploy-web.yml`, `flutter-ci.yml`, `release-clients.yml`, `windows-installer-ci.yml`,
  `secret-scan.yml`, `infra-ci.yml` — backendové projekty nereferencují (ověřeno grepem).

**Odkazy mimo CI, které se vědomě nemění:** `infra/helm/zdrive/templates/auth-service.yaml`
+ `values.yaml`, `infra/terraform/container-apps/**` (7 apps), `docs/releases/0.2.0.md`
(historie), `docs/superpowers/specs/*`. Do PR description napsat, že Helm/Terraform
jsou mimo produkční cestu (produkce = App Service ZIP deploy) a aktualizují se až
s případnou migrací na Container Apps.

**Rollback:** jeden PR, jeden `git revert`. Ve stromu se nic negeneruje (žádné nové
migrace — kontexty a schémata se nemění, `__EFMigrationsHistory` per schéma zůstává),
takže revert obnoví 4 Api projekty beze ztráty. V Azure zůstávají 3 staré App Services
až do ručního smazání (sekce 10), tj. i nasazení jde vrátit přepnutím gateway clusterů
zpět (staré ZIPy jsou v `%USERPROFILE%/.zdrive/deployment-backups/`).

**Rizika, na která si dát pozor při implementaci:**
1. `AddJwtBearer` 4× → startup pád. Řeší 2a/1. Test: `dotnet run` merged hosta.
2. Health check jméno `database` 4× → startup pád. Řeší 2b. Test: `GET /health/ready`.
3. `AddApplication`/`AddInfrastructure` ambiguita → CS0121. Řeší plná kvalifikace.
4. Testovací factory migrující jen 1 kontext → ostatní 3 se připojují na `localhost:5432`
   → CI padne. Řeší sekce 6 (override 4 klíčů).
5. Env proměnná `ZDRIVE_DEV_KEY_DIR` v BackupCli testech — dál platí pro 1 host.
6. Serilog `Service` property = `Api` (Seq dashboardy).
7. Startup je teď součet 4 migrací + 4 DbContext model buildů — první request po
   cold startu delší; kompenzuje R2R a AlwaysOn (sekce 10).

**Pořadí pro agenta (každý krok = build zelený):**
1. Sekce 2a (Shared `ValidationBehavior`, strip JWT z 3 Infrastructure) → `dotnet build`.
2. Vytvořit `src/services/Api` (csproj, Program.cs, appsettings, launchSettings,
   Dockerfile, přesun controllerů + middleware), přidat do sln → `dotnet build`,
   `dotnet run` + `GET /health/ready` = 200 se 4 checky, `/swagger` ukazuje 7 prefixů.
3. Smazat 4 Api projekty + 4 Dockerfily, odebrat ze sln → `dotnet build` (odhalí
   zbylé reference).
4. Testy (sekce 6) → `dotnet test` unit + integration zelené.
5. Gateway (sekce 5) → `ApiGateway.Tests` zelené; ručně gateway `:5100` → merged `:5101`
   login + list files.
6. Swagger podmínka v Photo/Notification (sekce 7), `Directory.Build.props` (sekce 8)
   → `dotnet publish -r linux-x64` merged hosta projde.
7. README/CLAUDE.md/docker-compose.prod.yml/deploy-test.yml/api_constants komentář.

---

## 10. Manuální Azure follow-up (pro člověka, NE pro coding agenta)

Předpoklad: PR z tohoto plánu je zmergovaný, `dotnet publish src/services/Api -c Release
-r linux-x64 --self-contained false` vytvořil ZIP. Vše v RG `invoiceapi`, plán
`asp-fakvio-b1`. Pořadí zvoleno tak, aby gateway nikdy neukazovala na prázdnou app.

1. **Zvolit cílovou app pro merged deploy: `zdrive-auth`** (přebírá roli „api";
   přejmenování App Service nejde, nový název by znamenal novou app = nové outbound IP
   na stejném plánu, což firewall Postgresu už pokrývá — ale zbytečně). Alternativa:
   založit `zdrive-api` a `zdrive-auth` smazat s ostatními — víc kroků, stejný výsledek.
2. **App settings na `zdrive-auth` doplnit** (hodnoty opsat z `zdrive-file`/`-storage`/`-sync`):
   `ConnectionStrings__FileDb`, `ConnectionStrings__StorageDb`, `ConnectionStrings__SyncDb`
   (stejný server jako `AuthDb`, liší se jen `Search Path=files|storage|sync`),
   `AZURE_STORAGE_CONNECTION_STRING` (nebo `ConnectionStrings__AzureBlobStorage`),
   `Sharing__DownloadGrantKey` (stejná hodnota, jakou má dnes file i storage),
   `Versioning__MaxVersionsPerFile` / `Storage__DefaultUserQuotaBytes` pokud jsou
   přebité. `Jwt__RsaPrivateKeyPem` + `Jwt__RsaPublicKeyPem` tam už jsou (auth).
3. **Zapnout AlwaysOn na `zdrive-auth`** (dnes jen gateway; cold start 4 kontextů by byl
   delší než dnešních ~48 s u storage). Paměťově je to pořád méně než 4 procesy.
4. `az webapp deploy --resource-group invoiceapi --name zdrive-auth --src-path api.zip
   --type zip --clean true --restart true --timeout 600000`; ověřit
   `https://zdrive-auth.../health/ready` = 200 (4 checky) a
   `POST /api/v1/auth/login` přímo proti app.
5. **Gateway app settings** (`zdrive-gateway`): odstranit
   `ReverseProxy__Clusters__{auth,file,storage,sync}Cluster__Destinations__*__Address`,
   přidat `ReverseProxy__Clusters__apiCluster__Destinations__apiService__Address =
   https://zdrive-auth.azurewebsites.net` (nebo custom doména). Pak nasadit nový
   gateway ZIP (má nové routy → bez nového ZIPu by staré routy ukazovaly na
   neexistující clustery). Pořadí: nejdřív app setting, pak ZIP + restart — restart
   načte oboje najednou; okno výpadku = restart gateway (sekundy).
6. Smoke přes gateway: login → list → upload → download → sync pull; `/health/ready`.
7. **Po ověření (ne dřív, kvůli rollbacku): smazat App Services `zdrive-file`,
   `zdrive-storage`, `zdrive-sync`.** Plán zůstává (sdílený s fakvio). DNS: klient
   i web míří na gateway, přímé hostnames tří služeb nikdo nepoužívá → žádná DNS změna.
8. Rollback před krokem 7: vrátit gateway app settings na 4 clustery + starý gateway
   ZIP ze zálohy; staré 3 apps ještě běží. Po kroku 7 = redeploy 3 apps ze záložních
   ZIPů (`~/.zdrive/deployment-backups/`) + jejich app settings (ty záloha ZIPů
   neobsahuje — před krokem 7 exportovat `az webapp config appsettings list` pro
   všechny 3).
