using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Xunit;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Domain.Enums;
using ZDrive.Shared.DTOs;
using SharedJwt = ZDrive.Shared.Auth.JwtConstants;

namespace ZDrive.SyncService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class SyncFlowTests : IClassFixture<SyncServiceFactory>
{
    private readonly HttpClient _client;
    private readonly Guid _userId = Guid.NewGuid();

    public SyncFlowTests(SyncServiceFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", GenerateTestJwt(_userId));
    }

    [Fact]
    public async Task RegisterDevice_PushEvents_PullFromAnotherDevice_FullFlow()
    {
        // Register device A
        var deviceAResponse = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Desktop Windows",
            platform = (int)DevicePlatform.Windows
        });
        deviceAResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var deviceAResult = await deviceAResponse.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>();
        deviceAResult!.Success.Should().BeTrue();
        var deviceA = deviceAResult.Data!;
        deviceA.Name.Should().Be("Desktop Windows");
        deviceA.Platform.Should().Be("Windows");

        // Register device B
        var deviceBResponse = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "iPhone",
            platform = (int)DevicePlatform.iOS
        });
        deviceBResponse.StatusCode.Should().Be(HttpStatusCode.Created);
        var deviceBResult = await deviceBResponse.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>();
        var deviceB = deviceBResult!.Data!;

        // Push events from device A
        var fileId = Guid.NewGuid();
        var pushResponse = await _client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = deviceA.Id,
            events = new[]
            {
                new { fileId, eventType = (int)SyncEventType.Create, metadata = (string?)"{\"name\":\"test.txt\"}" },
                new { fileId, eventType = (int)SyncEventType.Update, metadata = (string?)null }
            }
        });
        pushResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var pushResult = await pushResponse.Content.ReadFromJsonAsync<ApiResponse<PushResultDto>>();
        pushResult!.Success.Should().BeTrue();
        pushResult.Data!.NewCursor.Should().BeGreaterThan(0);
        pushResult.Data.Conflicts.Should().BeEmpty();

        // Pull from device B (should see events from device A)
        var pullResponse = await _client.PostAsJsonAsync("/api/v1/sync/pull", new
        {
            deviceId = deviceB.Id,
            cursor = 0L
        });
        pullResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var pullResult = await pullResponse.Content.ReadFromJsonAsync<ApiResponse<PullResultDto>>();
        pullResult!.Success.Should().BeTrue();
        pullResult.Data!.Events.Should().HaveCount(2);
        pullResult.Data.Events[0].FileId.Should().Be(fileId);
        pullResult.Data.Events[0].EventType.Should().Be("Create");
        pullResult.Data.Events[1].EventType.Should().Be("Update");
        pullResult.Data.NewCursor.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task PushConflictingChanges_ConflictCreated()
    {
        // Register two devices
        var deviceAResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Device A",
            platform = (int)DevicePlatform.Windows
        });
        var deviceA = (await deviceAResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        var deviceBResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Device B",
            platform = (int)DevicePlatform.MacOS
        });
        var deviceB = (await deviceBResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        var fileId = Guid.NewGuid();

        // Device A pushes an update
        await _client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = deviceA.Id,
            events = new[] { new { fileId, eventType = (int)SyncEventType.Update, metadata = (string?)null } }
        });

        // Device B pushes an update on the same file (without having pulled first) -- should conflict
        var conflictPush = await _client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = deviceB.Id,
            events = new[] { new { fileId, eventType = (int)SyncEventType.Update, metadata = (string?)null } }
        });
        conflictPush.StatusCode.Should().Be(HttpStatusCode.OK);

        var pushResult = await conflictPush.Content.ReadFromJsonAsync<ApiResponse<PushResultDto>>();
        pushResult!.Data!.Conflicts.Should().NotBeEmpty();
        pushResult.Data.Conflicts[0].FileId.Should().Be(fileId);
        pushResult.Data.Conflicts[0].Status.Should().Be("Pending");
    }

    [Fact]
    public async Task ResolveConflict_StatusUpdated()
    {
        // Register two devices and create a conflict
        var deviceAResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Resolve-A",
            platform = (int)DevicePlatform.Windows
        });
        var deviceA = (await deviceAResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        var deviceBResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Resolve-B",
            platform = (int)DevicePlatform.MacOS
        });
        var deviceB = (await deviceBResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        var fileId = Guid.NewGuid();

        await _client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = deviceA.Id,
            events = new[] { new { fileId, eventType = (int)SyncEventType.Update, metadata = (string?)null } }
        });

        var conflictPush = await _client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = deviceB.Id,
            events = new[] { new { fileId, eventType = (int)SyncEventType.Update, metadata = (string?)null } }
        });
        var pushResult = (await conflictPush.Content.ReadFromJsonAsync<ApiResponse<PushResultDto>>())!.Data!;
        var conflictId = pushResult.Conflicts[0].Id;

        // Resolve the conflict
        var resolveResp = await _client.PostAsJsonAsync($"/api/v1/sync/conflicts/{conflictId}/resolve", new
        {
            resolution = (int)ConflictResolution.KeepLocal
        });
        resolveResp.StatusCode.Should().Be(HttpStatusCode.OK);

        var resolveResult = await resolveResp.Content.ReadFromJsonAsync<ApiResponse<bool>>();
        resolveResult!.Data.Should().BeTrue();

        // Verify conflicts list shows resolved status
        var conflictsResp = await _client.GetAsync("/api/v1/sync/conflicts");
        var conflicts = (await conflictsResp.Content.ReadFromJsonAsync<ApiResponse<List<SyncConflictDto>>>())!.Data!;
        conflicts.Should().Contain(c => c.Id == conflictId && c.Status == "ResolvedLocal");
    }

    [Fact]
    public async Task CursorPagination_Push100Events_PullWithCursor_VerifyOrdering()
    {
        var deviceAResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Pagination-A",
            platform = (int)DevicePlatform.Windows
        });
        var deviceA = (await deviceAResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        var deviceBResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "Pagination-B",
            platform = (int)DevicePlatform.Android
        });
        var deviceB = (await deviceBResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        // Push 100 events from device A
        var events = Enumerable.Range(0, 100)
            .Select(_ => new { fileId = Guid.NewGuid(), eventType = (int)SyncEventType.Create, metadata = (string?)null })
            .ToList();

        await _client.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = deviceA.Id,
            events
        });

        // Pull from device B with cursor 0
        var pullResp = await _client.PostAsJsonAsync("/api/v1/sync/pull", new
        {
            deviceId = deviceB.Id,
            cursor = 0L
        });
        var pullResult = (await pullResp.Content.ReadFromJsonAsync<ApiResponse<PullResultDto>>())!.Data!;

        pullResult.Events.Should().HaveCount(100);
        pullResult.NewCursor.Should().BeGreaterThan(0);

        // Verify ordering: IDs should be strictly ascending
        for (int i = 1; i < pullResult.Events.Count; i++)
        {
            pullResult.Events[i].Id.Should().BeGreaterThan(pullResult.Events[i - 1].Id);
        }

        // Pull again with the new cursor should return no events
        var pullResp2 = await _client.PostAsJsonAsync("/api/v1/sync/pull", new
        {
            deviceId = deviceB.Id,
            cursor = pullResult.NewCursor
        });
        var pullResult2 = (await pullResp2.Content.ReadFromJsonAsync<ApiResponse<PullResultDto>>())!.Data!;
        pullResult2.Events.Should().BeEmpty();
        pullResult2.NewCursor.Should().Be(pullResult.NewCursor);
    }

    [Fact]
    public async Task UnregisterDevice_DeviceRemoved()
    {
        // Register
        var registerResp = await _client.PostAsJsonAsync("/api/v1/sync/devices", new
        {
            name = "To be removed",
            platform = (int)DevicePlatform.Web
        });
        var device = (await registerResp.Content.ReadFromJsonAsync<ApiResponse<DeviceDto>>())!.Data!;

        // List devices - should contain the registered device
        var listResp1 = await _client.GetAsync("/api/v1/sync/devices");
        var devices1 = (await listResp1.Content.ReadFromJsonAsync<ApiResponse<List<DeviceDto>>>())!.Data!;
        devices1.Should().Contain(d => d.Id == device.Id);

        // Unregister
        var deleteResp = await _client.DeleteAsync($"/api/v1/sync/devices/{device.Id}");
        deleteResp.StatusCode.Should().Be(HttpStatusCode.OK);

        // List devices - should no longer contain the removed device
        var listResp2 = await _client.GetAsync("/api/v1/sync/devices");
        var devices2 = (await listResp2.Content.ReadFromJsonAsync<ApiResponse<List<DeviceDto>>>())!.Data!;
        devices2.Should().NotContain(d => d.Id == device.Id);
    }

    /// <summary>
    /// Generates a test JWT matching the RSA public key in appsettings.json.
    /// The private key here is the pair to the public key already configured.
    /// </summary>
    private static string GenerateTestJwt(Guid userId)
    {
        // This is the private key corresponding to the public key in appsettings.json.
        // Only used for testing.
        const string privateKeyPem = """
            -----BEGIN RSA PRIVATE KEY-----
            MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/ygWeGNGMBAH/KFocmwMIi1AadTa0vf0V
            VVkMDEJHMJx5JOFdqrxiMvOqFr0GDzrB8f6jXHRBJF5YBplPMakldqtHPKP+f2jP
            JA8+7m+0q8NGVelL3VfdhaIuhy6UPiMxZ+K/lbYNiIFBOYHecaZOVfE3FGFhqWig
            B5U/L/aGkI7lMBP2LBmWcnXBfWfmVG+OBBqExW+WNKQR/g14J3k2eCmfs8fUps1
            PNY/MEbBVz0MjMqWJISdJPf/kAAA99xXMT1vDHMlakG3jbGc5rLgh8WOGx3WjC1S
            tYJBLSxFPx9qbXx+20NiWNMunm2FXPY8a5S1ewwIDAQABAoIBAC5RgZ+hBx7xHNaM
            pPgwGMnCd3KE8F8ZBJj4H8gCdWCnMrSY/bHGUwCo0gPClDB4xHPkUO/Sx3QLSEU
            K+n/fjBaGUSJn1jPx5X9Y+PujMFaj0gEBODOv3uJBmpPMDIT+VdgfcBEMnXwSKzM
            RYbXeJkJd0t0bKPaBRHo3qWmAi3M6sFB/BKhPF8z/TtN3csBgaIc/L+xpO1mBOe
            rlKQ3VUNB8nvnBFBBV16+h/HZGLjWVALBHxNQaijJfR+ohpHxaXbwJQFEmrubQ3I
            8LRFnMFfPviX8mHHxiPnVzlM99A2TdI7S1dMcfhJNJHEBqTLGQRzG4cNu+EavOl
            M0k/LoECgYEA6VGUxHd/I/XPgGn7fBoKoCECrM2CcaM0p4IWYfSpQIBjcI8C/Ly0
            Nc9IMFJK0cGCAJlK6QhDGN2BV1KQEK+mBdC08yffOWN+3RfwFLTi7C0IBjCsM5O
            HgBxe2mC1fZ0OuAnUYJ1VQHEra2ODeYYk5G4oKPNkJkaq/3MyG+o5wECgYEA5b2r
            Fxq+kOQ4uIEWmnVD+Y7gV4I1E1GAMHnV+cWfoAPC+i4PZfLI2aCjAzgJb9I1JIpH
            nIKbhWgcsFXAESdE3K8zKFcKK1Uw11xKPQRACXr8/yNa+jdJSaHjjFYnRTdGGSVF
            VqmXotQmqPr9B0JiwYL71UnG3l6U5l/EA78oi8MCgYBmDxZ8wXS/vNKaPG2rUm6O
            QGs+j1KhDB/xcuiQsFwdQNX61yrCyRHYpInyj9h0ISmUl+VVmf+MtQtcMlidRpVa
            +fh7grj3EfVgLB96cH8eN1Y1z/PMVDloR1UDan7FCRE6qF1Rf5aU4dL01yvbJxlK
            NqJW9yzP3rLkqK/U1kvAAQKBgQC00U7ICAKPyQmKbJleLT5fNdi3VleX9A0w/4Hn
            Ee5r1sFDr+xlGfHVBdLCiTfWKTCEDLdGSiF9VJR4tWSRYmGXxDBYKl+/pE7aXGLk
            MxGMn0j7fKVcpO0F5Y6VGv2shg0MgSz1D4WmKC0F3QIElu/EOMM7R+ELb/4z7F2V
            4zfPNwKBgQDXFiD6w5b0J3XPWlxjh3FJI0iqpAK9HjVfOQ65Kqm5Al3DqDE9TwnV
            azjuuCqFI7pLq3oiT/TcUaUzrDKTpJmMOh7Vrr3aFKVGB3cIiE5Z7uawWJRxNyqO
            G/KO4sN9QElGMQzl+j3woS/I0J5X1cJ/VTf3tN+G9aKkJoSOqgzNcQ==
            -----END RSA PRIVATE KEY-----
            """;

        var rsa = RSA.Create();
        rsa.ImportFromPem(privateKeyPem);

        var signingCredentials = new SigningCredentials(
            new RsaSecurityKey(rsa), SecurityAlgorithms.RsaSha256);

        var claims = new[]
        {
            new Claim(SharedJwt.UserIdClaim, userId.ToString()),
            new Claim(SharedJwt.TenantIdClaim, Guid.NewGuid().ToString()),
            new Claim(SharedJwt.RoleClaim, "Owner"),
            new Claim(SharedJwt.DisplayNameClaim, "Test User")
        };

        var token = new JwtSecurityToken(
            issuer: "zdrive",
            audience: "zdrive-api",
            claims: claims,
            expires: DateTime.UtcNow.AddHours(1),
            signingCredentials: signingCredentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
