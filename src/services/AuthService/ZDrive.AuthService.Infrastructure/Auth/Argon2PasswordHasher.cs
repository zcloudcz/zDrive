using System.Text;
using Isopoh.Cryptography.Argon2;
using ZDrive.AuthService.Application.Interfaces;

namespace ZDrive.AuthService.Infrastructure.Auth;

public sealed class Argon2PasswordHasher : IPasswordHasher
{
    public string Hash(string password)
    {
        return Argon2.Hash(password);
    }

    public bool Verify(string password, string hash)
    {
        return Argon2.Verify(hash, password);
    }
}
