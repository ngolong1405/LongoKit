using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

namespace LongoShare;

/// <summary>How this device shows itself and takes files.</summary>
public sealed class ShareSettings
{
    /// <summary>The name others see.</summary>
    public string Alias { get; set; } = Environment.MachineName;
    public int Port { get; set; } = Protocol.Port;
    /// <summary>HTTPS (LocalSend's default); off, plain HTTP, a little faster.</summary>
    public bool Encrypted { get; set; } = true;
    public string Folder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    public string? Pin { get; set; }
    /// <summary>Devices whose files come in without asking, by fingerprint.</summary>
    public HashSet<string> Trusted { get; set; } = new();
}

/// <summary>
/// One device on the network: its server (receiving), its client (sending) and discovery, with the devices it knows.
/// The UI drives this; tests run two of them side by side.
/// </summary>
public sealed class ShareNode : IDisposable
{
    private readonly X509Certificate2? certificate;
    private readonly ConcurrentDictionary<string, (Peer Peer, DateTime Seen)> peers = new();
    private HttpServer? server;
    private Discovery? discovery;

    public ShareSettings Settings { get; }
    public string Fingerprint { get; }
    public Receiver Receiver { get; }
    public Sender Sender { get; }
    /// <summary>The devices around, as last heard from.</summary>
    public IReadOnlyList<Peer> Peers => peers.Values.Select(p => p.Peer).OrderBy(p => p.Info.Alias, StringComparer.CurrentCultureIgnoreCase).ToList();
    public event Action? PeersChanged;
    /// <summary>The port the server listens on (the settings' one, or a free one when that's 0).</summary>
    public int Port => server?.Port ?? Settings.Port;

    /// <param name="certificatePath">Where this device's certificate is kept (made the first time).</param>
    public ShareNode(ShareSettings settings, string certificatePath)
    {
        Settings = settings;
        certificate = settings.Encrypted ? Certificate.LoadOrCreate(certificatePath) : null;
        Fingerprint = certificate != null ? Certificate.Fingerprint(certificate) : Guid.NewGuid().ToString("N");
        Receiver = new Receiver(() => Self) { Folder = settings.Folder, Pin = settings.Pin, Trusted = settings.Trusted };
        Receiver.Registered += Add;
        Sender = new Sender(() => Self);
    }

    public DeviceInfo Self => new()
    {
        Alias = Settings.Alias,
        DeviceModel = OperatingSystem.IsWindows() ? "Windows" : OperatingSystem.IsMacOS() ? "macOS" : OperatingSystem.IsLinux() ? "Linux" : RuntimeInformation.OSDescription,
        DeviceType = "desktop",
        Fingerprint = Fingerprint,
        Port = Port,
        Protocol = Settings.Encrypted ? "https" : "http",
    };

    /// <param name="discover">Multicast discovery too (tests on one machine leave it off).</param>
    public void Start(bool discover = true)
    {
        server = new HttpServer(Settings.Port, certificate, Receiver.Handle);
        server.Start();
        if (!discover) return;
        discovery = new Discovery(() => Self, (address, port, protocol) => Sender.Register(address, port, protocol));
        discovery.Found += Add;
        discovery.Start();
        discovery.Announce();
    }

    /// <summary>Looks for devices again: an announcement, then (if asked) every address of the local networks.</summary>
    public async Task Refresh(bool scan = true, CancellationToken token = default)
    {
        foreach (var (key, entry) in peers)
            if (DateTime.UtcNow - entry.Seen > TimeSpan.FromMinutes(2)) peers.TryRemove(key, out _);
        discovery?.Announce();
        if (scan && discovery != null) await discovery.Scan(Settings.Port, Settings.Encrypted ? "https" : "http", token);
        PeersChanged?.Invoke();
    }

    /// <summary>A device at <paramref name="address"/>, asked directly (typed in, or a test).</summary>
    public async Task<Peer?> Connect(string address, int port = Protocol.Port, string protocol = "https")
    {
        var peer = await Sender.Register(address, port, protocol);
        if (peer != null) Add(peer);
        return peer;
    }

    private void Add(Peer peer)
    {
        if (peer.Info.Fingerprint == Fingerprint) return;
        var key = string.IsNullOrEmpty(peer.Info.Fingerprint) ? peer.Address : peer.Info.Fingerprint;
        peers[key] = (peer, DateTime.UtcNow);
        PeersChanged?.Invoke();
    }

    public Task<SendResult> Send(Peer peer, IReadOnlyList<Outgoing> items, string? pin = null, Action<long, long>? progress = null,
                                 CancellationToken token = default) => Sender.Send(peer, items, pin, progress, token);

    public void Dispose()
    {
        discovery?.Dispose();
        server?.Dispose();
        Sender.Dispose();
    }
}
