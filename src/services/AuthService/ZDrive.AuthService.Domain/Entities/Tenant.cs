namespace ZDrive.AuthService.Domain.Entities;

public sealed class Tenant
{
    public Guid Id { get; set; }
    public required string Name { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public ICollection<User> Users { get; set; } = [];
}
