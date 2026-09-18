using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.ListSharedChildren;

public sealed record ListSharedChildrenQuery(string LinkToken, Guid? FolderId) : IRequest<List<FileDto>>;
