namespace ZDrive.Shared.Auth;

public static class Roles
{
    public const string Owner = "Owner";
    public const string Admin = "Admin";
    public const string Member = "Member";
    public const string Viewer = "Viewer";

    public static readonly IReadOnlyList<string> All = [Owner, Admin, Member, Viewer];
}
