using LongoKit.UI;

namespace LongoShare.Windows;

/// <summary>A device whose files come in without asking.</summary>
public sealed class TrustedDevice
{
    public string Fingerprint { get; set; } = "";
    public string Alias { get; set; } = "";
}

/// <summary>A transfer done, for History.</summary>
public sealed class HistoryItem
{
    public bool Sent { get; set; }
    public string Device { get; set; } = "";
    public List<string> Files { get; set; } = new();
    public string? Text { get; set; }
    public DateTime Time { get; set; }
}

/// <summary>What's saved.</summary>
public sealed class ShareState
{
    public bool IsEnabled { get; set; } = true;
    public string Alias { get; set; } = Environment.MachineName;
    public string Folder { get; set; } = AppFolder.Standard("Longo Share");
    public string? Pin { get; set; }
    public bool Encrypted { get; set; } = true;
    public List<TrustedDevice> Trusted { get; set; } = new();
    public List<HistoryItem> History { get; set; } = new();
}

/// <summary>A transfer under way, for the menu.</summary>
public sealed record Transfer(string Device, bool Sending, long Done, long Total);
