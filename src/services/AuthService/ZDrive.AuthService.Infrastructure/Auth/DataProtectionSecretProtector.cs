using Microsoft.AspNetCore.DataProtection;
using ZDrive.AuthService.Application.Interfaces;

namespace ZDrive.AuthService.Infrastructure.Auth;

public sealed class DataProtectionSecretProtector : ISecretProtector
{
    private readonly IDataProtector _protector;

    public DataProtectionSecretProtector(IDataProtectionProvider provider) =>
        _protector = provider.CreateProtector("ZDrive.AuthService.TwoFactorSecret");

    public string Protect(string plaintext) => _protector.Protect(plaintext);
    public string Unprotect(string protectedValue) => _protector.Unprotect(protectedValue);
}
