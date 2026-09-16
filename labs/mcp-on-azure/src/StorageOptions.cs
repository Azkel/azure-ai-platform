namespace McpOnAzure;

public sealed record StorageOptions(
    string AccountName,
    string ContainerName,
    string PlatformOnlyContainerName);
