using FluentValidation;

namespace ZDrive.PhotoService.Application.Queries.GetTimeline;

public sealed class GetTimelineQueryValidator : AbstractValidator<GetTimelineQuery>
{
    public GetTimelineQueryValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.TenantId).NotEmpty();
        RuleFor(x => x.Limit).InclusiveBetween(1, 200);
        RuleFor(x => x.Offset).GreaterThanOrEqualTo(0);
    }
}
