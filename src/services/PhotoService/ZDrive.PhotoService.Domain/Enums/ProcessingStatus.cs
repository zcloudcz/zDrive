namespace ZDrive.PhotoService.Domain.Enums;

public enum ProcessingStatus
{
    Pending = 0,
    Ingested = 1,
    Analyzed = 2,
    Complete = 3,
    Failed = 4
}
