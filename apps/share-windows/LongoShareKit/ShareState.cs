using LongoKit.UI;

namespace LongoShare.Windows;

/// <summary>A device whose files come in without asking.</summary>
public sealed class TrustedDevice
{
    public string Fingerprint { get; set; } = "";
    public string Alias { get; set; } = "";
}

/// <summary>A file in a chat: its name and size, and where it is on this PC (sent from, or saved to).</summary>
public sealed class ChatFile
{
    public string Name { get; set; } = "";
    public long Size { get; set; }
    public string? Path { get; set; }
}

/// <summary>Where a message stands.</summary>
public enum ChatState
{
    /// <summary>Coming in, waiting for the person here to accept or decline.</summary>
    Asking,
    /// <summary>Going out, waiting for the other side to accept.</summary>
    Waiting,
    /// <summary>The other side wants a PIN before it takes these.</summary>
    Pin,
    Transferring, Done, Declined, Failed, Cancelled,
}

/// <summary>One message in a chat with a device: text, or files, either way.</summary>
public sealed class ChatItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public bool Sent { get; set; }
    public string? Text { get; set; }
    public List<ChatFile> Files { get; set; } = new();
    public ChatState State { get; set; }
    public DateTime Time { get; set; } = DateTime.Now;
    public long Done { get; set; }
    public long Total { get; set; }

    public double Fraction => Total == 0 ? 0 : Math.Min(1, (double)Done / Total);
    public bool IsOpen => State is ChatState.Asking or ChatState.Waiting or ChatState.Pin or ChatState.Transferring;
}

/// <summary>The chat with one device, kept across launches (the device may not be around now).</summary>
public sealed class Conversation
{
    public string Id { get; set; } = "";
    public string Alias { get; set; } = "";
    public string? DeviceModel { get; set; }
    public string? DeviceType { get; set; }
    public List<ChatItem> Items { get; set; } = new();
    public int Unread { get; set; }

    public DateTime LastTime => Items.Count == 0 ? DateTime.MinValue : Items[^1].Time;
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
    public Dictionary<string, Conversation> Conversations { get; set; } = new();
}

/// <summary>A transfer under way, for the menu.</summary>
public sealed record Transfer(string Device, bool Sending, long Done, long Total);

/// <summary>A device in the list: one around now, or one chatted with before.</summary>
public sealed record Contact(string Id, DeviceInfo Info, Peer? Peer, Conversation? Conversation)
{
    public bool IsOnline => Peer != null;
}
