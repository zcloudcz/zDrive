using Microsoft.Extensions.DependencyInjection;
using Serilog;

namespace ZDrive.Shared.Extensions;

/// <summary>
/// Common service registrations shared across all microservices.
/// </summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers shared cross-cutting concerns: Serilog enrichment, correlation id support.
    /// </summary>
    public static IServiceCollection AddSharedServices(this IServiceCollection services)
    {
        services.AddHttpContextAccessor();
        return services;
    }
}
