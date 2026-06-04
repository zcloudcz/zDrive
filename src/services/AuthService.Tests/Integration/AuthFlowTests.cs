using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.AuthService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class AuthFlowTests : IClassFixture<AuthServiceFactory>
{
    private readonly HttpClient _client;

    public AuthFlowTests(AuthServiceFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Register_Login_Refresh_GetProfile_FullFlow()
    {
        // Register
        var registerResponse = await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            email = "flow@example.com",
            password = "Password1",
            displayName = "Flow User"
        });
        registerResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var registerResult = await registerResponse.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>();
        registerResult.Should().NotBeNull();
        registerResult!.Success.Should().BeTrue();
        registerResult.Data.Should().NotBeNull();
        registerResult.Data!.AccessToken.Should().NotBeNullOrWhiteSpace();
        registerResult.Data.RefreshToken.Should().NotBeNullOrWhiteSpace();

        // Login with same credentials
        var loginResponse = await _client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "flow@example.com",
            password = "Password1"
        });
        loginResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var loginResult = await loginResponse.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>();
        loginResult!.Success.Should().BeTrue();
        loginResult.Data!.AccessToken.Should().NotBeNullOrWhiteSpace();

        // Refresh token
        var refreshResponse = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = loginResult.Data.RefreshToken
        });
        refreshResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var refreshResult = await refreshResponse.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>();
        refreshResult!.Success.Should().BeTrue();
        refreshResult.Data!.AccessToken.Should().NotBeNullOrWhiteSpace();
        // New refresh token should differ from old one (rotation)
        refreshResult.Data.RefreshToken.Should().NotBe(loginResult.Data.RefreshToken);

        // Get profile using access token
        var profileRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/users/me");
        profileRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", refreshResult.Data.AccessToken);
        var profileResponse = await _client.SendAsync(profileRequest);
        profileResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var profileResult = await profileResponse.Content.ReadFromJsonAsync<ApiResponse<UserDto>>();
        profileResult!.Success.Should().BeTrue();
        profileResult.Data!.Email.Should().Be("flow@example.com");
        profileResult.Data.DisplayName.Should().Be("Flow User");
        profileResult.Data.Role.Should().Be("Owner");
    }

    [Fact]
    public async Task Register_DuplicateEmail_Returns409()
    {
        var payload = new { email = "duplicate@example.com", password = "Password1", displayName = "First" };

        var first = await _client.PostAsJsonAsync("/api/v1/auth/register", payload);
        first.StatusCode.Should().Be(HttpStatusCode.OK);

        var second = await _client.PostAsJsonAsync("/api/v1/auth/register", payload);
        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Login_InvalidCredentials_Returns404()
    {
        // Register first
        await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            email = "invalid-creds@example.com",
            password = "Password1",
            displayName = "User"
        });

        // Login with wrong password
        var response = await _client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "invalid-creds@example.com",
            password = "WrongPassword1"
        });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Refresh_ExpiredToken_Returns404()
    {
        // Use a non-existent refresh token
        var response = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = "non-existent-token"
        });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Refresh_TokenRotation_OldTokenInvalidated()
    {
        // Register
        var registerResponse = await _client.PostAsJsonAsync("/api/v1/auth/register", new
        {
            email = "rotation@example.com",
            password = "Password1",
            displayName = "Rotation User"
        });
        var registerResult = await registerResponse.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>();
        var originalRefreshToken = registerResult!.Data!.RefreshToken;

        // Use the refresh token once
        var firstRefresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = originalRefreshToken
        });
        firstRefresh.StatusCode.Should().Be(HttpStatusCode.OK);

        // Try to use the same refresh token again (should fail — it was rotated)
        var secondRefresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = originalRefreshToken
        });
        secondRefresh.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetProfile_WithoutToken_Returns401()
    {
        var response = await _client.GetAsync("/api/v1/users/me");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
