using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Xunit;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Infrastructure.Persistence;

namespace ZDrive.FileService.Tests.Integration;

// Pins PR #12 review round 4: ParentId is null for every root-level
// FileNode — the root is the synced folder itself, the most important place
// for sibling-name uniqueness to hold. Postgres treats null as distinct from
// null in a unique index by default, so before the CaseInsensitiveFileNames
// migration declared the index NULLS NOT DISTINCT, two root-level siblings
// differing only by case could both exist in the table at once: the index
// alone did not stop it, only CreateFileCommandHandler's AnyAsync check did
// (see FileFlowTests.CreateDuplicate_CaseOnlyDifference_Returns409), and two
// concurrent creates can race past an application-level check. This test
// goes around the handler and inserts straight through the DbContext, so it
// exercises the database constraint itself rather than the guard in front
// of it.
[Trait("Category", "Integration")]
public sealed class FileNodeUniqueIndexTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;

    public FileNodeUniqueIndexTests(FileServiceFactory factory) => _factory = factory;

    [Fact]
    public async Task UniqueIndex_CaseOnlyDuplicateAtRoot_SecondInsertRejectedByDatabase()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FileDbContext>();

        db.FileNodes.Add(new FileNode
        {
            Id = Guid.NewGuid(),
            UserId = _factory.TestUserId,
            TenantId = _factory.TestTenantId,
            ParentId = null, // root
            Name = "RootCaseIndex",
            IsFolder = true
        });
        await db.SaveChangesAsync();

        db.FileNodes.Add(new FileNode
        {
            Id = Guid.NewGuid(),
            UserId = _factory.TestUserId,
            TenantId = _factory.TestTenantId,
            ParentId = null, // same root — both rows have a null parent_id
            Name = "rootcaseindex", // differs from the row above only by case
            IsFolder = true
        });

        var act = () => db.SaveChangesAsync();

        var thrown = await act.Should().ThrowAsync<DbUpdateException>();
        thrown.WithInnerException<PostgresException>()
            .Which.SqlState.Should().Be(PostgresErrorCodes.UniqueViolation);
    }
}
