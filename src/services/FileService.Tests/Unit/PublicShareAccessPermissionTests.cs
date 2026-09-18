using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Domain.Entities;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Unit tests for the permission gate every write endpoint goes through
/// (RequireWrite / RequireDelete). AllowDelete is a separate, additive right
/// from Permission — a Write link without AllowDelete still can't delete,
/// and a Read+AllowDelete link (odd but allowed by the contract) still can.
/// </summary>
[Trait("Category", "Unit")]
public sealed class PublicShareAccessPermissionTests
{
    private static Share MakeShare(Permission permission, bool allowDelete = false) => new()
    {
        Id = Guid.NewGuid(),
        FileId = Guid.NewGuid(),
        SharedBy = Guid.NewGuid(),
        Permission = permission,
        AllowDelete = allowDelete,
        LinkToken = "token"
    };

    [Theory]
    [InlineData(Permission.Write)]
    [InlineData(Permission.Admin)]
    public void RequireWrite_WriteOrAdmin_DoesNotThrow(Permission permission)
    {
        var act = () => PublicShareAccess.RequireWrite(MakeShare(permission));
        act.Should().NotThrow();
    }

    [Fact]
    public void RequireWrite_ReadOnly_ThrowsForbidden()
    {
        var act = () => PublicShareAccess.RequireWrite(MakeShare(Permission.Read));
        act.Should().Throw<ForbiddenException>();
    }

    [Fact]
    public void RequireDelete_AllowDeleteTrue_DoesNotThrow_EvenOnReadOnlyLink()
    {
        // AllowDelete is additive, independent of Permission.
        var act = () => PublicShareAccess.RequireDelete(MakeShare(Permission.Read, allowDelete: true));
        act.Should().NotThrow();
    }

    [Fact]
    public void RequireDelete_AllowDeleteFalse_ThrowsForbidden_EvenOnWriteLink()
    {
        var act = () => PublicShareAccess.RequireDelete(MakeShare(Permission.Write, allowDelete: false));
        act.Should().Throw<ForbiddenException>();
    }
}
