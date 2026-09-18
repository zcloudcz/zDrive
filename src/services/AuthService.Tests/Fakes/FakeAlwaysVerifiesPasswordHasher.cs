using ZDrive.AuthService.Application.Interfaces;

namespace ZDrive.AuthService.Tests.Fakes;

/// <summary>
/// A password hasher that always says "match". Used to prove the null-hash
/// guard in LoginCommandHandler rejects Entra-only accounts on its own,
/// before the hasher would ever get a chance to say otherwise.
/// </summary>
public sealed class FakeAlwaysVerifiesPasswordHasher : IPasswordHasher
{
    public string Hash(string password) => "hash";
    public bool Verify(string password, string hash) => true;
}
