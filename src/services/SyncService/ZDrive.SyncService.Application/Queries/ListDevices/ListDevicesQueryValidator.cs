using FluentValidation;

namespace ZDrive.SyncService.Application.Queries.ListDevices;

public sealed class ListDevicesQueryValidator : AbstractValidator<ListDevicesQuery>
{
    public ListDevicesQueryValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
    }
}
