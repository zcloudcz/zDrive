using FluentAssertions;
using Xunit;
using ZDrive.AuthService.Infrastructure.Auth;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class Argon2PasswordHasherTests
{
    private readonly Argon2PasswordHasher _hasher = new();

    [Fact]
    public void Hash_ProducesNonEmptyString()
    {
        var hash = _hasher.Hash("MyPassword123");
        hash.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public void Hash_DifferentInputs_ProduceDifferentHashes()
    {
        var hash1 = _hasher.Hash("Password1");
        var hash2 = _hasher.Hash("Password2");
        hash1.Should().NotBe(hash2);
    }

    [Fact]
    public void Hash_SameInput_ProducesDifferentHashes_DueToSalt()
    {
        var hash1 = _hasher.Hash("SamePassword");
        var hash2 = _hasher.Hash("SamePassword");
        hash1.Should().NotBe(hash2);
    }

    [Fact]
    public void Verify_CorrectPassword_ReturnsTrue()
    {
        var password = "MySecurePassword123";
        var hash = _hasher.Hash(password);
        _hasher.Verify(password, hash).Should().BeTrue();
    }

    [Fact]
    public void Verify_WrongPassword_ReturnsFalse()
    {
        var hash = _hasher.Hash("CorrectPassword");
        _hasher.Verify("WrongPassword", hash).Should().BeFalse();
    }
}
