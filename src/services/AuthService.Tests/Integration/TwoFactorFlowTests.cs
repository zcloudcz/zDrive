using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.AuthService.Application.DTOs;
using ZDrive.AuthService.Infrastructure.Persistence;
using ZDrive.AuthService.Tests.Fakes;
using ZDrive.Shared.DTOs;

namespace ZDrive.AuthService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class TwoFactorFlowTests : IClassFixture<AuthServiceFactory>
{
    private const string Password = "Password1";

    private readonly AuthServiceFactory _factory;
    private readonly HttpClient _client;

    public TwoFactorFlowTests(AuthServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private sealed record Account(string Email, string AccessToken, string RefreshToken = "");

    private async Task<Account> RegisterAsync()
    {
        var email = $"{Guid.NewGuid():N}@example.com";
        var response = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new { email, password = Password, displayName = "TwoFactor User" });
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>();
        return new Account(email, body!.Data!.AccessToken, body.Data.RefreshToken);
    }

    private Task<HttpResponseMessage> PostAuthed(string accessToken, string url, object? body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = JsonContent.Create(body ?? new { })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        return _client.SendAsync(request);
    }

    private async Task<TwoFactorSetupDto> SetupAsync(Account account)
    {
        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/setup", new { password = Password });
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<TwoFactorSetupDto>>())!.Data!;
    }

    // Confirm with the previous step's code so the current and next step stay
    // free for the login / disable calls of the same test.
    private async Task<IReadOnlyList<string>> EnableAsync(Account account, string secret)
    {
        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/confirm",
            new { code = TwoFactorTestSupport.CodeFor(secret, DateTime.UtcNow.AddSeconds(-30)) });
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<RecoveryCodesDto>>())!.Data!.RecoveryCodes;
    }

    private async Task<LoginResultDto> LoginAsync(string email)
    {
        var response = await _client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password });
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<LoginResultDto>>())!.Data!;
    }

    private Task<HttpResponseMessage> CompleteLoginAsync(string challenge, string? code = null, string? recoveryCode = null) =>
        _client.PostAsJsonAsync("/api/v1/auth/login/2fa", new { challengeToken = challenge, code, recoveryCode });

    [Fact]
    public async Task Login_UserWithoutTwoFactor_ReturnsTokensWithBackwardCompatibleShape()
    {
        var account = await RegisterAsync();

        var response = await _client.PostAsJsonAsync("/api/v1/auth/login", new { email = account.Email, password = Password });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var raw = await response.Content.ReadAsStringAsync();
        raw.Should().Contain("\"accessToken\":\"").And.Contain("\"refreshToken\":\"").And.Contain("\"expiresAt\":");
        raw.Should().Contain("\"twoFactorRequired\":false");
    }

    [Fact]
    public async Task Setup_Authenticated_ReturnsSecretAndOtpAuthUri()
    {
        var account = await RegisterAsync();

        var setup = await SetupAsync(account);

        setup.Secret.Should().NotBeNullOrWhiteSpace();
        setup.OtpAuthUri.Should().StartWith("otpauth://totp/zDrive:").And.Contain($"secret={setup.Secret}");
    }

    [Fact]
    public async Task Setup_Unauthenticated_Returns401()
    {
        var response = await _client.PostAsJsonAsync("/api/v1/users/me/2fa/setup", new { });

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Setup_AlreadyEnabled_Returns409()
    {
        var account = await RegisterAsync();
        await EnableAsync(account, (await SetupAsync(account)).Secret);

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/setup", new { password = Password });

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Setup_EntraOnlyAccount_Returns403()
    {
        var account = await RegisterAsync();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            var user = db.Users.Single(u => u.Email == account.Email);
            user.PasswordHash = null;
            await db.SaveChangesAsync();
        }

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/setup", new { password = Password });

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Confirm_ValidCode_EnablesTwoFactorAndStoresSecretEncrypted()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);

        var recoveryCodes = await EnableAsync(account, setup.Secret);

        recoveryCodes.Should().HaveCount(10);
        var me = await GetMeAsync(account);
        me.TwoFactorEnabled.Should().BeTrue();
        me.HasPassword.Should().BeTrue();

        using var scope = _factory.Services.CreateScope();
        var stored = scope.ServiceProvider.GetRequiredService<AuthDbContext>()
            .Users.Single(u => u.Email == account.Email).TwoFactorSecretProtected;
        stored.Should().NotBeNullOrEmpty().And.NotContain(setup.Secret);
    }

    [Fact]
    public async Task Confirm_WrongCode_Returns400AndLeavesTwoFactorOff()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/confirm", new { code = wrong });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await GetMeAsync(account)).TwoFactorEnabled.Should().BeFalse();
    }

    [Fact]
    public async Task Disable_ValidPasswordAndCode_TurnsTwoFactorOff()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/disable",
            new { password = Password, code = TwoFactorTestSupport.CodeFor(setup.Secret) });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await response.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>())!.Data!.RefreshToken.Should().NotBeNullOrEmpty();
        (await GetMeAsync(account)).TwoFactorEnabled.Should().BeFalse();
        (await LoginAsync(account.Email)).TwoFactorRequired.Should().BeFalse();
    }

    [Fact]
    public async Task Disable_WrongPassword_Returns400AndKeepsTwoFactor()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/disable",
            new { password = "WrongPassword1", code = TwoFactorTestSupport.CodeFor(setup.Secret) });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await GetMeAsync(account)).TwoFactorEnabled.Should().BeTrue();
    }

    [Fact]
    public async Task LoginTwoFactor_PasswordThenCode_IssuesWorkingTokens()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);

        var login = await LoginAsync(account.Email);
        login.TwoFactorRequired.Should().BeTrue();
        login.AccessToken.Should().BeNull();
        login.RefreshToken.Should().BeNull();

        var response = await CompleteLoginAsync(login.ChallengeToken!, code: TwoFactorTestSupport.CodeFor(setup.Secret));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var tokens = (await response.Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>())!.Data!;
        var me = await GetMeAsync(new Account(account.Email, tokens.AccessToken));
        me.Email.Should().Be(account.Email);
    }

    [Fact]
    public async Task LoginTwoFactor_WrongCode_Returns400WithoutTokens()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var login = await LoginAsync(account.Email);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);

        var response = await CompleteLoginAsync(login.ChallengeToken!, code: valid == "000000" ? "000001" : "000000");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await response.Content.ReadAsStringAsync()).Should().NotContain("accessToken");
    }

    [Fact]
    public async Task LoginTwoFactor_ChallengeUsedTwice_SecondAttemptRejected()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var login = await LoginAsync(account.Email);
        (await CompleteLoginAsync(login.ChallengeToken!, code: TwoFactorTestSupport.CodeFor(setup.Secret)))
            .StatusCode.Should().Be(HttpStatusCode.OK);

        // Next step's code is valid TOTP-wise; only the spent challenge is wrong.
        var response = await CompleteLoginAsync(login.ChallengeToken!,
            code: TwoFactorTestSupport.CodeFor(setup.Secret, DateTime.UtcNow.AddSeconds(30)));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task LoginTwoFactor_ExpiredChallenge_Rejected()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var login = await LoginAsync(account.Email);
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            var challenge = db.TwoFactorChallenges.Single(c => c.User.Email == account.Email);
            challenge.ExpiresAt = DateTime.UtcNow.AddMinutes(-1);
            await db.SaveChangesAsync();
        }

        var response = await CompleteLoginAsync(login.ChallengeToken!, code: TwoFactorTestSupport.CodeFor(setup.Secret));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task LoginTwoFactor_SameTotpCodeTwice_SecondLoginRejected()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var code = TwoFactorTestSupport.CodeFor(setup.Secret);
        var first = await LoginAsync(account.Email);
        (await CompleteLoginAsync(first.ChallengeToken!, code: code)).StatusCode.Should().Be(HttpStatusCode.OK);

        var second = await LoginAsync(account.Email);
        var response = await CompleteLoginAsync(second.ChallengeToken!, code: code);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task LoginTwoFactor_RecoveryCode_WorksExactlyOnce()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        var recoveryCodes = await EnableAsync(account, setup.Secret);

        var first = await LoginAsync(account.Email);
        (await CompleteLoginAsync(first.ChallengeToken!, recoveryCode: recoveryCodes[0])).StatusCode.Should().Be(HttpStatusCode.OK);

        var second = await LoginAsync(account.Email);
        var response = await CompleteLoginAsync(second.ChallengeToken!, recoveryCode: recoveryCodes[0]);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task LoginTwoFactor_FreshHostSameDatabase_DecryptsSecretWithKeyFromDatabase()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);

        // A second host: its own DI container and key cache, same Postgres.
        // It can only decrypt the stored secret if the key ring lives in the DB.
        await using var otherHost = _factory.WithWebHostBuilder(_ => { });
        var otherClient = otherHost.CreateClient();

        var loginResponse = await otherClient.PostAsJsonAsync("/api/v1/auth/login",
            new { email = account.Email, password = Password });
        var login = (await loginResponse.Content.ReadFromJsonAsync<ApiResponse<LoginResultDto>>())!.Data!;
        login.TwoFactorRequired.Should().BeTrue();

        var response = await otherClient.PostAsJsonAsync("/api/v1/auth/login/2fa", new
        {
            challengeToken = login.ChallengeToken,
            code = TwoFactorTestSupport.CodeFor(setup.Secret)
        });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        using var scope = _factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<AuthDbContext>().DataProtectionKeys.Should().NotBeEmpty();
    }

    [Fact]
    public async Task LoginTwoFactor_MissingCode_Returns400()
    {
        var response = await CompleteLoginAsync("whatever");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Setup_WrongPassword_Returns400()
    {
        var account = await RegisterAsync();

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/setup", new { password = "WrongPassword1" });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Setup_SecondCallWithinTenMinutes_ReturnsTheSamePendingSecret()
    {
        var account = await RegisterAsync();
        var first = await SetupAsync(account);

        var second = await SetupAsync(account);

        second.Secret.Should().Be(first.Secret);
    }

    [Fact]
    public async Task Confirm_ReturnsFreshTokens_AndOldRefreshTokenIsRejected()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);

        var response = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/confirm",
            new { code = TwoFactorTestSupport.CodeFor(setup.Secret, DateTime.UtcNow.AddSeconds(-30)) });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = (await response.Content.ReadFromJsonAsync<ApiResponse<RecoveryCodesDto>>())!.Data!;
        body.RefreshToken.Should().NotBe(account.RefreshToken);
        var oldRefresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = account.RefreshToken });
        oldRefresh.StatusCode.Should().Be(HttpStatusCode.NotFound, "the refresh endpoint answers a revoked token like an unknown one");
        var newRefresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = body.RefreshToken });
        newRefresh.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Disable_ReturnsFreshTokens_AndOldRefreshTokenIsRejected()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var login = await LoginAsync(account.Email);
        var session = (await (await CompleteLoginAsync(login.ChallengeToken!,
            code: TwoFactorTestSupport.CodeFor(setup.Secret))).Content.ReadFromJsonAsync<ApiResponse<AuthTokenDto>>())!.Data!;

        // Next step's code: the login above used the current one.
        var response = await PostAuthed(session.AccessToken, "/api/v1/users/me/2fa/disable",
            new { password = Password, code = TwoFactorTestSupport.CodeFor(setup.Secret, DateTime.UtcNow.AddSeconds(30)) });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var oldRefresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = session.RefreshToken });
        oldRefresh.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Disable_WrongPasswordAndWrongCode_ReturnIdenticalBodies()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        var badPassword = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/disable",
            new { password = "WrongPassword1", code = valid });
        var badCode = await PostAuthed(account.AccessToken, "/api/v1/users/me/2fa/disable",
            new { password = Password, code = wrong });

        badPassword.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        badCode.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await badPassword.Content.ReadAsStringAsync()).Should().Be(await badCode.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task LoginTwoFactor_ParallelWrongCodesOnOneChallenge_AreCappedAtFiveAndNeverFail500()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var login = await LoginAsync(account.Email);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        var responses = await Task.WhenAll(Enumerable.Range(0, 30)
            .Select(_ => CompleteLoginAsync(login.ChallengeToken!, code: wrong)));

        responses.Should().OnlyContain(r => r.StatusCode == HttpStatusCode.BadRequest);
        using (var scope = _factory.Services.CreateScope())
        {
            var challenge = scope.ServiceProvider.GetRequiredService<AuthDbContext>()
                .TwoFactorChallenges.Single(c => c.User.Email == account.Email);
            challenge.FailedAttempts.Should().Be(5, "parallel guesses share the 5-attempt cap");
        }

        // Burned: even the right code no longer works.
        (await CompleteLoginAsync(login.ChallengeToken!, code: valid)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task LoginTwoFactor_WrongCodesAcrossChallenges_HitThePerUserCap()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        for (var i = 0; i < 10; i++)
        {
            var login = await LoginAsync(account.Email);
            (await CompleteLoginAsync(login.ChallengeToken!, code: wrong)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        }

        var last = await LoginAsync(account.Email);
        var response = await CompleteLoginAsync(last.ChallengeToken!, code: valid);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest, "10 failed attempts per user are allowed per window");
    }

    [Fact]
    public async Task LoginTwoFactor_SameValidCodeInParallelOnSeparateChallenges_ExactlyOneSucceedsNoneFail500()
    {
        var account = await RegisterAsync();
        var setup = await SetupAsync(account);
        await EnableAsync(account, setup.Secret);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);
        var challenges = new List<string>();
        for (var i = 0; i < 4; i++)
            challenges.Add((await LoginAsync(account.Email)).ChallengeToken!);

        var responses = await Task.WhenAll(challenges.Select(c => CompleteLoginAsync(c, code: valid)));

        responses.Count(r => r.StatusCode == HttpStatusCode.OK).Should().Be(1);
        responses.Where(r => r.StatusCode != HttpStatusCode.OK).Should().OnlyContain(r => r.StatusCode == HttpStatusCode.BadRequest);
    }

    private async Task<UserDto> GetMeAsync(Account account)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/users/me");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", account.AccessToken);
        var response = await _client.SendAsync(request);
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<UserDto>>())!.Data!;
    }
}
