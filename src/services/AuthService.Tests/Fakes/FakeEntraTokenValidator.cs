using ZDrive.AuthService.Application.Interfaces;

namespace ZDrive.AuthService.Tests.Fakes;

/// <summary>
/// Stands in for the real token validator (which fetches signing keys over
/// the network) in handler unit tests — configured per test with either an
/// identity to return or an exception to throw. Never asserts anything itself.
/// </summary>
public sealed class FakeEntraTokenValidator : IEntraTokenValidator
{
    private readonly EntraIdentity? _identity;
    private readonly Exception? _exception;

    private FakeEntraTokenValidator(EntraIdentity? identity, Exception? exception)
    {
        _identity = identity;
        _exception = exception;
    }

    public static FakeEntraTokenValidator Returning(EntraIdentity identity) => new(identity, null);
    public static FakeEntraTokenValidator Throwing(Exception exception) => new(null, exception);

    public Task<EntraIdentity> ValidateAsync(string accessToken, CancellationToken ct)
    {
        if (_exception is not null)
            throw _exception;

        return Task.FromResult(_identity!);
    }
}

/// <summary>
/// Same seam as <see cref="FakeEntraTokenValidator"/>, but mutable and
/// registered once per DI container — needed for integration tests, where
/// the factory (and its container) is shared across several test cases via
/// IClassFixture and each case configures its own behavior before calling
/// the endpoint. Safe for concurrent ValidateAsync calls (e.g. a test firing
/// several requests at once with Task.WhenAll): reference reads/writes are
/// atomic in .NET, and every test sets both properties once, before issuing
/// any requests — there is no concurrent writer to race against.
/// </summary>
public sealed class MutableFakeEntraTokenValidator : IEntraTokenValidator
{
    public EntraIdentity? IdentityToReturn { get; set; }
    public Exception? ExceptionToThrow { get; set; }

    public Task<EntraIdentity> ValidateAsync(string accessToken, CancellationToken ct)
    {
        if (ExceptionToThrow is not null)
            throw ExceptionToThrow;

        if (IdentityToReturn is null)
            throw new InvalidOperationException("Test forgot to configure MutableFakeEntraTokenValidator.");

        return Task.FromResult(IdentityToReturn);
    }
}
