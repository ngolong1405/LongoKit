using System.Net.Sockets;
using System.Text;
using System.Windows.Threading;
using LongoKit.UI;

namespace LongoShare.Windows;

/// <summary>What happened last, shown under the devices: an English line (through L) and the device it's about.</summary>
public sealed record Notice(string Text, string Device = "", bool Good = true);

/// <summary>
/// Longo Share's state for the UI: the settings, the device (<see cref="ShareNode"/>) while it's on, the devices
/// around, the transfer under way and the history. Calls from the network come back on the UI's thread.
/// </summary>
public sealed class ShareModel
{
    private const int HistoryLength = 100;
    private readonly ShareState state;
    private readonly bool isSample;
    /// <summary>The UI's thread, from Start (the module is made before the app runs).</summary>
    private Dispatcher? ui;
    private ShareNode? node;
    private Timer? announcer;
    private CancellationTokenSource? sending;
    private IReadOnlyList<Peer> samplePeers = Array.Empty<Peer>();
    private DateTime lastProgress;
    private string receivingFrom = "";

    /// <summary>Something shown changed.</summary>
    public event Action? Changed;
    /// <summary>Asks the person whether to take files (a window); true takes them.</summary>
    public Func<IncomingTransfer, Task<bool>> Ask { get; set; } = _ => Task.FromResult(false);
    /// <summary>Asks for the PIN a device wants; null gives up.</summary>
    public Func<Peer, Task<string?>> AskPin { get; set; } = _ => Task.FromResult<string?>(null);
    /// <summary>A message came in: shows it.</summary>
    public Action<Peer, string> ShowMessage { get; set; } = (_, _) => { };

    public Transfer? Current { get; private set; }
    public Notice? Notice { get; private set; }
    /// <summary>Why it can't receive (the port is taken...), or null.</summary>
    public string? Problem { get; private set; }
    public string ProblemDetail { get; private set; } = "";
    public bool IsScanning { get; private set; }

    public ShareModel(ShareState? sample = null)
    {
        state = sample ?? Store.Load<ShareState>("share");
        isSample = sample != null;
    }

    // MARK: - Settings

    public bool IsEnabled
    {
        get => state.IsEnabled;
        set
        {
            if (state.IsEnabled == value) return;
            state.IsEnabled = value;
            Save();
            if (value) Start();
            else Stop();
        }
    }

    public string Alias
    {
        get => state.Alias;
        set
        {
            value = value.Trim();
            if (value.Length == 0 || value == state.Alias) return;
            state.Alias = value;
            if (node != null)
            {
                node.Settings.Alias = value;
                _ = node.Refresh(scan: false);
            }
            Save();
        }
    }

    public string Folder
    {
        get => state.Folder;
        set
        {
            state.Folder = value;
            if (node != null) node.Settings.Folder = node.Receiver.Folder = value;
            Save();
        }
    }

    /// <summary>A PIN senders must give, or null.</summary>
    public string? Pin
    {
        get => state.Pin;
        set
        {
            state.Pin = string.IsNullOrWhiteSpace(value) ? null : value.Trim();
            if (node != null) node.Settings.Pin = node.Receiver.Pin = state.Pin;
            Save();
        }
    }

    /// <summary>HTTPS, as LocalSend has it; off, plain HTTP. Changing it starts the server again.</summary>
    public bool Encrypted
    {
        get => state.Encrypted;
        set
        {
            if (state.Encrypted == value) return;
            state.Encrypted = value;
            Save();
            if (node != null)
            {
                Stop();
                Start();
            }
        }
    }

    public IReadOnlyList<TrustedDevice> Trusted => state.Trusted;
    public IReadOnlyList<HistoryItem> History => state.History;

    public bool IsTrusted(Peer peer) => state.Trusted.Any(t => t.Fingerprint == peer.Info.Fingerprint);

    public void SetTrusted(Peer peer, bool trusted)
    {
        var fingerprint = peer.Info.Fingerprint;
        if (string.IsNullOrEmpty(fingerprint)) return;
        state.Trusted.RemoveAll(t => t.Fingerprint == fingerprint);
        if (trusted) state.Trusted.Add(new TrustedDevice { Fingerprint = fingerprint, Alias = peer.Info.Alias });
        SyncTrusted();
        Save();
    }

    public void Forget(TrustedDevice device)
    {
        state.Trusted.RemoveAll(t => t.Fingerprint == device.Fingerprint);
        SyncTrusted();
        Save();
    }

    public void ClearHistory()
    {
        state.History.Clear();
        Save();
    }

    private void SyncTrusted()
    {
        if (node == null) return;
        node.Settings.Trusted.Clear();
        foreach (var device in state.Trusted) node.Settings.Trusted.Add(device.Fingerprint);
    }

    private void Save()
    {
        if (!isSample) Store.Save("share", state);
        Notify();
    }

    // MARK: - Running

    /// <summary>This PC, as others see it.</summary>
    public string Address => Discovery.LocalAddresses().FirstOrDefault()?.ToString() ?? "";
    public int Port => node?.Port ?? Protocol.Port;

    public IReadOnlyList<Peer> Peers => node?.Peers ?? samplePeers;

    public void Start()
    {
        if (isSample || !state.IsEnabled || node != null) return;
        ui = Dispatcher.CurrentDispatcher;
        var settings = new ShareSettings
        {
            Alias = state.Alias, Encrypted = state.Encrypted, Folder = state.Folder, Pin = state.Pin,
            Trusted = new HashSet<string>(state.Trusted.Select(t => t.Fingerprint)),
        };
        try
        {
            node = new ShareNode(settings, Path.Combine(Store.Folder, "share-certificate.pfx"));
            node.Receiver.Ask = transfer => transfer.Text != null ? Task.FromResult(true) : OnUi(() => Ask(transfer));
            node.Receiver.Accepted += transfer => receivingFrom = transfer.From.Info.Alias;
            node.Receiver.Progress += (done, total) => Progressed(new Transfer(receivingFrom, false, done, total));
            node.Receiver.Received += received => Post(() => Received(received));
            node.Receiver.Cancelled += () => Post(() => Finish(new Notice("Transfer stopped.", Good: false)));
            node.PeersChanged += () => Post(Notify);
            node.Start();
            Problem = null;
        }
        catch (Exception error)
        {
            node?.Dispose();
            node = null;
            Problem = error is SocketException
                ? "Port {0} is taken by another app (LocalSend?). Quit it, then turn Longo Share off and on."
                : "Couldn't start receiving: {0}";
            ProblemDetail = error.Message;
        }
        if (node == null)
        {
            Notify();
            return;
        }
        // Now and then, an announcement: others answer, and those that left drop off the list.
        announcer = new Timer(_ => _ = node?.Refresh(scan: false), null, TimeSpan.FromSeconds(60), TimeSpan.FromSeconds(60));
        _ = Refresh();
        Notify();
    }

    public void Stop()
    {
        announcer?.Dispose();
        announcer = null;
        sending?.Cancel();
        node?.Dispose();
        node = null;
        Current = null;
        Problem = null;
        Notify();
    }

    /// <summary>Looks for devices: an announcement, then every address on the network.</summary>
    public async Task Refresh()
    {
        if (node == null || IsScanning) return;
        IsScanning = true;
        Notify();
        try
        {
            await node.Refresh();
        }
        catch (Exception)
        {
            // Not on a network: nothing found.
        }
        IsScanning = false;
        Notify();
    }

    /// <summary>Adds a device by its address, for when it isn't found on its own.</summary>
    public async Task<bool> Connect(string address)
    {
        if (node == null || string.IsNullOrWhiteSpace(address)) return false;
        var text = address.Trim();
        var port = Protocol.Port;
        if (text.LastIndexOf(':') is var colon and > 0 && text.Count(c => c == ':') == 1 && int.TryParse(text[(colon + 1)..], out var typed))
        {
            port = typed;
            text = text[..colon];
        }
        var peer = await node.Connect(text, port, "https") ?? await node.Connect(text, port, "http");
        Notice = peer != null ? new Notice("Found {0}.", peer.Info.Alias) : new Notice("Nothing answered at {0}.", address.Trim(), false);
        Notify();
        return peer != null;
    }

    // MARK: - Sending

    public Task SendFiles(Peer peer, IEnumerable<string> paths) =>
        Send(peer, paths.Where(File.Exists).Select(Outgoing.File).ToList());

    public Task SendText(Peer peer, string text) =>
        string.IsNullOrEmpty(text) ? Task.CompletedTask : Send(peer, new[] { Outgoing.Message(text) });

    private async Task Send(Peer peer, IReadOnlyList<Outgoing> items)
    {
        if (node == null || items.Count == 0 || Current != null) return;
        var total = items.Sum(item => item.Text != null ? Encoding.UTF8.GetByteCount(item.Text) : new System.IO.FileInfo(item.Path!).Length);
        sending = new CancellationTokenSource();
        Current = new Transfer(peer.Info.Alias, true, 0, total);
        Notice = null;
        Notify();
        string? pin = null;
        SendResult result;
        while (true)
        {
            try
            {
                result = await node.Send(peer, items, pin, (done, all) => Progressed(new Transfer(peer.Info.Alias, true, done, all)), sending.Token);
            }
            catch (Exception)
            {
                result = SendResult.Failed;
            }
            if (result != SendResult.PinRequired) break;
            pin = await AskPin(peer);
            if (pin == null)
            {
                result = SendResult.Cancelled;
                break;
            }
        }
        sending = null;
        var name = peer.Info.Alias;
        if (result == SendResult.Sent)
            Remember(new HistoryItem
            {
                Sent = true, Device = name, Time = DateTime.Now,
                Files = items.Where(i => i.Path != null).Select(i => Path.GetFileName(i.Path!)).ToList(),
                Text = items.FirstOrDefault(i => i.Text != null)?.Text,
            });
        Finish(result switch
        {
            SendResult.Sent => new Notice("Sent to {0}.", name),
            SendResult.Rejected => new Notice("{0} declined.", name, false),
            SendResult.Busy => new Notice("{0} is busy with another transfer.", name, false),
            SendResult.Cancelled => new Notice("Cancelled."),
            _ => new Notice("Couldn't reach {0}.", name, false),
        });
    }

    /// <summary>Stops the transfer under way, either way.</summary>
    public void Cancel()
    {
        if (sending != null) sending.Cancel();
        else node?.Receiver.Cancel();
    }

    // MARK: - Receiving

    private void Received(ReceivedTransfer received)
    {
        Remember(new HistoryItem
        {
            Sent = false, Device = received.From.Info.Alias, Time = DateTime.Now, Text = received.Text,
            Files = received.Files.Select(Path.GetFileName).OfType<string>().ToList(),
        });
        if (received.Text != null)
        {
            ShowMessage(received.From, received.Text);
            Notify();
            return;
        }
        Finish(new Notice("Received from {0}.", received.From.Info.Alias));
    }

    private void Remember(HistoryItem item)
    {
        state.History.Insert(0, item);
        if (state.History.Count > HistoryLength) state.History.RemoveRange(HistoryLength, state.History.Count - HistoryLength);
        Save();
    }

    private void Finish(Notice notice)
    {
        Current = null;
        Notice = notice;
        Notify();
    }

    /// <summary>Progress, from the network's threads: shown at most ten times a second.</summary>
    private void Progressed(Transfer transfer)
    {
        Current = transfer;
        var now = DateTime.UtcNow;
        if (now - lastProgress < TimeSpan.FromMilliseconds(100) && transfer.Done < transfer.Total) return;
        lastProgress = now;
        Post(Notify);
    }

    // MARK: - Threads

    private void Notify() => Changed?.Invoke();

    private void Post(Action action)
    {
        if (ui == null) action();
        else ui.BeginInvoke(action);
    }

    private Task<T> OnUi<T>(Func<Task<T>> work)
    {
        if (ui == null) return work();
        return ui.InvokeAsync(work).Task.Unwrap();
    }

    // MARK: - Sample data

    /// <summary>Devices, a transfer and history, for the pages' pictures.</summary>
    public void Simulate(IReadOnlyList<Peer> peers, Transfer? current, Notice? notice)
    {
        samplePeers = peers;
        Current = current;
        Notice = notice;
        Notify();
    }
}
