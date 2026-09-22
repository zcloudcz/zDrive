using FluentValidation;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Services;

namespace ZDrive.FileService.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = typeof(DependencyInjection).Assembly;

        services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));
        services.AddValidatorsFromAssembly(assembly);
        services.AddScoped<IStorageQuota, StorageQuota>();

        return services;
    }
}
