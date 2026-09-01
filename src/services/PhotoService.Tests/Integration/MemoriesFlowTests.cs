using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class MemoriesFlowTests : IClassFixture<PhotoServiceFactory>
{
    private readonly PhotoServiceFactory _factory;
    private readonly HttpClient _client;

    public MemoriesFlowTests(PhotoServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    // Memories are only ever produced by the (out-of-scope) AI generation
    // pipeline — there is no API to create one, so tests seed directly via
    // the DbContext, exactly like the daily cron job would.
    private async Task<Memory> SeedMemoryAsync(string title = "This day, 2 years ago")
    {
        var memory = new Memory
        {
            Id = Guid.NewGuid(),
            UserId = _factory.TestUserId,
            Type = MemoryType.ThisDay,
            Title = title,
            DateFrom = DateTime.UtcNow.AddYears(-2),
            DateTo = DateTime.UtcNow.AddYears(-2),
            PhotoIds = [],
            Seen = false
        };

        await _factory.SeedAsync(async db =>
        {
            db.Memories.Add(memory);
            await db.SaveChangesAsync();
        });
        return memory;
    }

    [Fact]
    public async Task GetAll_UnseenMemorySeeded_ReturnsIt()
    {
        var memory = await SeedMemoryAsync();

        var response = await _client.GetAsync("/api/v1/memories");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var memories = await response.Content.ReadFromJsonAsync<List<MemoryDto>>();
        memories.Should().Contain(m => m.Id == memory.Id);
    }

    [Fact]
    public async Task Dismiss_ExistingMemory_NoLongerInGetAll()
    {
        var memory = await SeedMemoryAsync();

        var dismissResponse = await _client.PostAsync($"/api/v1/memories/{memory.Id}/dismiss", null);
        dismissResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var listResponse = await _client.GetAsync("/api/v1/memories");
        var memories = await listResponse.Content.ReadFromJsonAsync<List<MemoryDto>>();
        memories.Should().NotContain(m => m.Id == memory.Id);
    }

    [Fact]
    public async Task Dismiss_NonExistingMemory_Returns404()
    {
        var response = await _client.PostAsync($"/api/v1/memories/{Guid.NewGuid()}/dismiss", null);
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetAll_WithoutAuth_Returns401()
    {
        // No bearer token attached — reuses the shared fixture's server instead
        // of spinning up a second Postgres container just for this check.
        using var unauthClient = _factory.CreateClient();
        var response = await unauthClient.GetAsync("/api/v1/memories");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
