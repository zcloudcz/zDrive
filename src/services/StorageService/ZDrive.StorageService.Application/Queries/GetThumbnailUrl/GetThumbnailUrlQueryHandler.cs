using MediatR;
using Microsoft.Extensions.Configuration;

namespace ZDrive.StorageService.Application.Queries.GetThumbnailUrl;

public sealed class GetThumbnailUrlQueryHandler : IRequestHandler<GetThumbnailUrlQuery, string>
{
    private readonly string _cdnBaseUrl;

    public GetThumbnailUrlQueryHandler(IConfiguration configuration)
    {
        _cdnBaseUrl = configuration["CdnBaseUrl"] ?? "https://cdn.zdrive.io";
    }

    public Task<string> Handle(GetThumbnailUrlQuery request, CancellationToken cancellationToken)
    {
        var url = $"{_cdnBaseUrl}/{request.TenantId}/{request.UserId}/thumbnails/{request.PhotoId}/{request.Size}.webp";
        return Task.FromResult(url);
    }
}
