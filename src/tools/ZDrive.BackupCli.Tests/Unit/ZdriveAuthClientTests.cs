using System.Net;
using System.Text;
using FluentAssertions;
using ZDrive.BackupCli.Api;

namespace ZDrive.BackupCli.Tests.Unit;

public sealed class ZdriveAuthClientTests
{
    private sealed class StubHandler(string json) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            });
    }

    private static ZdriveAuthClient ClientReturning(string json) =>
        new(new HttpClient(new StubHandler(json)) { BaseAddress = new Uri("http://localhost/api/v1/") });

    [Fact]
    public async Task Login_TwoFactorRequired_FailsWithClearMessageNotJsonException()
    {
        var client = ClientReturning(
            """{"success":true,"data":{"accessToken":null,"refreshToken":null,"expiresAt":null,"twoFactorRequired":true,"challengeToken":"x"}}""");

        var act = () => client.LoginAsync("a@b.com", "Password1", default);

        (await act.Should().ThrowAsync<ZdriveApiException>())
            .Which.Message.Should().Contain("two-factor").And.Contain("BackupCli does not support");
        client.AccessToken.Should().BeNull();
    }

    [Fact]
    public async Task Login_NormalAccount_StoresAccessToken()
    {
        var client = ClientReturning(
            """{"success":true,"data":{"accessToken":"at","refreshToken":"rt","expiresAt":"2030-01-01T00:00:00Z","twoFactorRequired":false,"challengeToken":null}}""");

        await client.LoginAsync("a@b.com", "Password1", default);

        client.AccessToken.Should().Be("at");
    }

    [Fact]
    public async Task Login_ResponseWithoutTokens_Fails()
    {
        var client = ClientReturning("""{"success":true,"data":{"twoFactorRequired":false}}""");

        var act = () => client.LoginAsync("a@b.com", "Password1", default);

        await act.Should().ThrowAsync<ZdriveApiException>();
    }
}
