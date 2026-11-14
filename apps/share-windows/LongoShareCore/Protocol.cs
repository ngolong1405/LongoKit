using System.Text.Json;
using System.Text.Json.Serialization;

namespace LongoShare;

/// <summary>
/// The LocalSend protocol, v2 (github.com/localsend/protocol): the same field names and paths, so Longo Share and
/// LocalSend (Android, iOS, Linux...) find each other and send files both ways.
/// </summary>
public static class Protocol
{
    public const string Version = "2.1";
    public const int Port = 53317;
    public const string MulticastAddress = "224.0.0.167";
    public const string Base = "/api/localsend/v2";
    public const string Register = Base + "/register";
    public const string Info = Base + "/info";
    public const string PrepareUpload = Base + "/prepare-upload";
    public const string Upload = Base + "/upload";
    public const string Cancel = Base + "/cancel";

    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = true,
    };
}

/// <summary>What a device says about itself: in announcements, /register and prepare-upload.</summary>
public sealed record DeviceInfo
{
    public string Alias { get; init; } = "";
    public string Version { get; init; } = global::LongoShare.Protocol.Version;
    public string? DeviceModel { get; init; }
    /// <summary>mobile, desktop, web, headless or server.</summary>
    public string? DeviceType { get; init; } = "desktop";
    public string Fingerprint { get; init; } = "";
    public int Port { get; init; } = global::LongoShare.Protocol.Port;
    /// <summary>"https" or "http".</summary>
    public string Protocol { get; init; } = "https";
    public bool Download { get; init; }
    /// <summary>In a multicast message: true asks the others to answer; false is an answer.</summary>
    public bool? Announce { get; init; }
}

public sealed record FileMetadata
{
    public DateTimeOffset? Modified { get; init; }
    public DateTimeOffset? Accessed { get; init; }
}

/// <summary>A file offered in prepare-upload.</summary>
public sealed record FileInfo
{
    public string Id { get; init; } = "";
    public string FileName { get; init; } = "";
    public long Size { get; init; }
    /// <summary>A MIME type, like image/png.</summary>
    public string FileType { get; init; } = "application/octet-stream";
    public string? Sha256 { get; init; }
    public string? Preview { get; init; }
    public FileMetadata? Metadata { get; init; }
}

public sealed record PrepareUploadRequest
{
    public DeviceInfo Info { get; init; } = new();
    public Dictionary<string, FileInfo> Files { get; init; } = new();
}

public sealed record PrepareUploadResponse
{
    public string SessionId { get; init; } = "";
    /// <summary>A token per file id, to upload it with.</summary>
    public Dictionary<string, string> Files { get; init; } = new();
}

/// <summary>A device found on the network, and where to reach it.</summary>
public sealed record Peer(DeviceInfo Info, string Address)
{
    public Uri BaseUri => new($"{Info.Protocol}://{(Address.Contains(':') ? $"[{Address}]" : Address)}:{Info.Port}");
}
