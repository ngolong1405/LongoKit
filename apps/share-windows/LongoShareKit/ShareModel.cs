using System.Net.Sockets;
using System.Text;
using System.Windows.Threading;
using LongoKit.UI;

namespace LongoShare.Windows;

/// <summary>
/// Longo Share's state for the UI: the settings, the device (<see cref="ShareNode"/>) while it's on, the devices
/// around, and a chat with each one, where files and text come and go and incoming transfers are answered. Calls from
/// the network come back on the UI's thread.
/// </summary>
public sealed class ShareModel
{
    /// <summary>Messages kept per chat.</summary>
    private const int ChatLength = 300;
    private readonly ShareState state;
    private readonly bool isSample;
    /// <summary>The UI's thread, from Start (the module is made before the app runs).</summary>
    private Dispatcher? ui;
    private ShareNode? node;
    private Timer? announcer;
    private DispatcherTimer? saveTimer;
    private readonly Dictionary<Guid, CancellationTokenSource> sending = new();
    /// <summary>Answers the person gives in a chat: an incoming request's, or a PIN.</summary>
    private readonly Dictionary<Guid, TaskCompletionSource<bool>> answers = new();
    private readonly Dictionary<Guid, TaskCompletionSource<string?>> pins = new();
    /// <summary>The incoming transfer under way: its chat and message.</summary>
    private (string Conversation, Guid Item)? incoming;
    private IReadOnlyList<Peer> samplePeers = Array.Empty<Peer>();
    private DateTime lastProgress;
    private string? selected;

    /// <summary>Something shown changed.</summary>
    public event Action? Changed;
    /// <summary>Something came in while the window isn't showing the chats: the window should open on this one.</summary>
    public event Action<string>? WantsWindow;

    /// <summary>Why it can't receive (the port is taken...), or null.</summary>
    public string? Problem { get; private set; }
    public string ProblemDetail { get; private set; } = "";
    public bool IsScanning { get; private set; }
    public string? LastAddressFailed { get; private set; }
    /// <summary>Whether the window shows the chats now (set by the page), so a message there is seen at once.</summary>
    public bool ChatOnScreen { get; set; }

    public ShareModel(ShareState? sample = null)
    {
        state = sample ?? Store.Load<ShareState>("share");
        isSample = sample != null;
        // Its own folder in Downloads, made now (Downloads itself, the old default, moves there).
        if (!isSample) state.Folder = AppFolder.Resolve(state.Folder, "Longo Share");
        // What was under way when the app quit didn't finish.
        foreach (var item in state.Conversations.Values.SelectMany(c => c.Items).Where(i => i.IsOpen)) item.State = ChatState.Failed;
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
            try
            {
                Directory.CreateDirectory(value);
            }
            catch (Exception)
            {
                // Saving says so when it happens.
            }
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

    public bool IsTrusted(DeviceInfo info) => state.Trusted.Any(t => t.Fingerprint == info.Fingerprint);

    public void SetTrusted(DeviceInfo info, bool trusted)
    {
        var fingerprint = info.Fingerprint;
        if (string.IsNullOrEmpty(fingerprint)) return;
        state.Trusted.RemoveAll(t => t.Fingerprint == fingerprint);
        if (trusted) state.Trusted.Add(new TrustedDevice { Fingerprint = fingerprint, Alias = info.Alias });
        SyncTrusted();
        Save();
    }

    public void Forget(TrustedDevice device)
    {
        state.Trusted.RemoveAll(t => t.Fingerprint == device.Fingerprint);
        SyncTrusted();
        Save();
    }

    private void SyncTrusted()
    {
        if (node == null) return;
        node.Settings.Trusted.Clear();
        foreach (var device in state.Trusted) node.Settings.Trusted.Add(device.Fingerprint);
    }

    /// <summary>Saved a moment later, once: chats change at every bit of progress.</summary>
    private void Save()
    {
        if (!isSample)
        {
            if (saveTimer == null)
            {
                saveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                saveTimer.Tick += (_, _) => SaveNow();
            }
            saveTimer.Stop();
            saveTimer.Start();
        }
        Notify();
    }

    /// <summary>Written now (also before quitting).</summary>
    public void SaveNow()
    {
        if (isSample) return;
        saveTimer?.Stop();
        Store.Save("share", state);
    }

    // MARK: - Devices and chats

    /// <summary>This PC, as others see it.</summary>
    public string Address => Discovery.LocalAddresses().FirstOrDefault()?.ToString() ?? "";
    public int Port => node?.Port ?? Protocol.Port;

    public IReadOnlyList<Peer> Peers => node?.Peers ?? samplePeers;

    /// <summary>Devices around now first, then the ones chatted with before, most recent first.</summary>
    public IReadOnlyList<Contact> Contacts
    {
        get
        {
            var list = Peers.Select(p => new Contact(p.Id, p.Info, p, state.Conversations.GetValueOrDefault(p.Id))).ToList();
            var online = list.Select(c => c.Id).ToHashSet();
            foreach (var conversation in state.Conversations.Values.Where(c => !online.Contains(c.Id)))
                list.Add(new Contact(conversation.Id,
                                     new DeviceInfo { Alias = conversation.Alias, DeviceModel = conversation.DeviceModel, DeviceType = conversation.DeviceType, Fingerprint = conversation.Id },
                                     null, conversation));
            return list.OrderByDescending(c => c.IsOnline)
                       .ThenByDescending(c => c.Conversation?.LastTime ?? DateTime.MinValue)
                       .ThenBy(c => c.Info.Alias, StringComparer.CurrentCultureIgnoreCase)
                       .ToList();
        }
    }

    public Contact? Contact(string? id) => id == null ? null : Contacts.FirstOrDefault(c => c.Id == id);

    /// <summary>The chat on screen.</summary>
    public string? Selected
    {
        get => selected;
        set
        {
            selected = value;
            if (value != null && state.Conversations.TryGetValue(value, out var conversation) && conversation.Unread > 0)
            {
                conversation.Unread = 0;
                Save();
            }
            Notify();
        }
    }

    public int Unread => state.Conversations.Values.Sum(c => c.Unread);

    /// <summary>The transfer under way, if any.</summary>
    public Transfer? Current
    {
        get
        {
            foreach (var conversation in state.Conversations.Values)
                if (conversation.Items.LastOrDefault(i => i.State == ChatState.Transferring) is { } item)
                    return new Transfer(conversation.Alias, item.Sent, item.Done, item.Total);
            return null;
        }
    }

    public void Clear(string id)
    {
        if (!state.Conversations.TryGetValue(id, out var conversation)) return;
        conversation.Items.RemoveAll(i => !i.IsOpen);
        if (conversation.Items.Count == 0 && Peers.All(p => p.Id != id)) state.Conversations.Remove(id);
        Save();
    }

    private void Append(ChatItem item, string id, DeviceInfo info)
    {
        if (!state.Conversations.TryGetValue(id, out var conversation))
            state.Conversations[id] = conversation = new Conversation { Id = id, Alias = info.Alias, DeviceModel = info.DeviceModel, DeviceType = info.DeviceType };
        conversation.Items.Add(item);
        if (conversation.Items.Count > ChatLength) conversation.Items.RemoveRange(0, conversation.Items.Count - ChatLength);
        if (!item.Sent && !(ChatOnScreen && selected == id))
        {
            conversation.Unread++;
            if (!ChatOnScreen) WantsWindow?.Invoke(id);
            else if (selected == null) selected = id;
        }
        Save();
    }

    private ChatItem? Find(Guid id) => state.Conversations.Values.SelectMany(c => c.Items).FirstOrDefault(i => i.Id == id);

    private void Update(Guid id, Action<ChatItem> change)
    {
        if (Find(id) is not { } item) return;
        change(item);
        Save();
    }

    // MARK: - Running

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
            node.Receiver.Ask = transfer => transfer.Text != null ? Task.FromResult(true) : OnUi(() => AskToAccept(transfer));
            node.Receiver.Accepted += transfer => Post(() => Accepted(transfer));
            node.Receiver.Progress += (done, total) => Receiving(done, total);
            node.Receiver.Received += received => Post(() => Received(received));
            node.Receiver.Cancelled += () => Post(IncomingEnded);
            node.PeersChanged += () => Post(PeersChanged);
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
        foreach (var token in sending.Values) token.Cancel();
        foreach (var (id, answer) in answers.ToList())
        {
            answer.TrySetResult(false);
            Update(id, i => i.State = ChatState.Cancelled);
        }
        answers.Clear();
        foreach (var pin in pins.Values) pin.TrySetResult(null);
        pins.Clear();
        node?.Dispose();
        node = null;
        Problem = null;
        Notify();
    }

    private void PeersChanged()
    {
        // A device's chat follows its new name.
        foreach (var peer in Peers)
            if (state.Conversations.TryGetValue(peer.Id, out var conversation) && conversation.Alias != peer.Info.Alias)
                conversation.Alias = peer.Info.Alias;
        if (selected == null && Peers.Count > 0) selected = Peers[0].Id;
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
        PeersChanged();
    }

    /// <summary>Adds a device by its address, for when it isn't found on its own.</summary>
    public async Task Connect(string address)
    {
        if (node == null || string.IsNullOrWhiteSpace(address)) return;
        var text = address.Trim();
        var port = Protocol.Port;
        if (text.LastIndexOf(':') is var colon and > 0 && text.Count(c => c == ':') == 1 && int.TryParse(text[(colon + 1)..], out var typed))
        {
            port = typed;
            text = text[..colon];
        }
        var peer = await node.Connect(text, port, "https") ?? await node.Connect(text, port, "http");
        LastAddressFailed = peer == null ? text : null;
        if (peer != null) selected = peer.Id;
        PeersChanged();
    }

    // MARK: - Sending

    public void SendFiles(Peer peer, IEnumerable<string> paths)
    {
        var files = paths.Where(File.Exists).ToList();
        if (files.Count == 0) return;
        var chatFiles = files.Select(f => new ChatFile { Name = Path.GetFileName(f), Size = new System.IO.FileInfo(f).Length, Path = f }).ToList();
        _ = Send(peer, files.Select(Outgoing.File).ToList(),
                 new ChatItem { Sent = true, Files = chatFiles, State = ChatState.Waiting, Total = chatFiles.Sum(f => f.Size) });
    }

    public void SendText(Peer peer, string text)
    {
        text = text.Trim();
        if (text.Length == 0) return;
        _ = Send(peer, new[] { Outgoing.Message(text) },
                 new ChatItem { Sent = true, Text = text, State = ChatState.Waiting, Total = Encoding.UTF8.GetByteCount(text) });
    }

    private async Task Send(Peer peer, IReadOnlyList<Outgoing> items, ChatItem item)
    {
        if (node == null) return;
        Append(item, peer.Id, peer.Info);
        var token = new CancellationTokenSource();
        sending[item.Id] = token;
        string? pin = null;
        SendResult result;
        while (true)
        {
            try
            {
                result = await node.Send(peer, items, pin, (done, all) => Progressed(item.Id, done, all), token.Token);
            }
            catch (Exception)
            {
                result = SendResult.Failed;
            }
            if (token.IsCancellationRequested) result = SendResult.Cancelled;
            if (result != SendResult.PinRequired) break;
            Update(item.Id, i => i.State = ChatState.Pin);
            var asked = new TaskCompletionSource<string?>();
            pins[item.Id] = asked;
            pin = await asked.Task;
            if (pin == null)
            {
                result = SendResult.Cancelled;
                break;
            }
            Update(item.Id, i => i.State = ChatState.Waiting);
        }
        sending.Remove(item.Id);
        Update(item.Id, i =>
        {
            i.State = result switch
            {
                SendResult.Sent => ChatState.Done,
                SendResult.Rejected => ChatState.Declined,
                SendResult.Cancelled => ChatState.Cancelled,
                _ => ChatState.Failed,
            };
            if (result == SendResult.Sent) i.Done = i.Total;
        });
    }

    /// <summary>The PIN the other side asked for (null gives up).</summary>
    public void AnswerPin(Guid item, string? pin)
    {
        if (pins.Remove(item, out var asked)) asked.TrySetResult(string.IsNullOrWhiteSpace(pin) ? null : pin.Trim());
    }

    /// <summary>Stops a message under way, either way.</summary>
    public void Cancel(Guid item)
    {
        if (sending.TryGetValue(item, out var token))
        {
            token.Cancel();
            AnswerPin(item, null);
        }
        else if (incoming?.Item == item)
        {
            node?.Receiver.Cancel();
        }
    }

    /// <summary>Progress, from the network's threads: shown at most ten times a second.</summary>
    private void Progressed(Guid id, long done, long total)
    {
        var now = DateTime.UtcNow;
        if (now - lastProgress < TimeSpan.FromMilliseconds(100) && done < total) return;
        lastProgress = now;
        Post(() =>
        {
            if (!sending.ContainsKey(id)) return;
            Update(id, i =>
            {
                i.State = ChatState.Transferring;
                i.Done = done;
                i.Total = total;
            });
        });
    }

    // MARK: - Receiving

    private async Task<bool> AskToAccept(IncomingTransfer transfer)
    {
        var item = new ChatItem
        {
            Sent = false, State = ChatState.Asking, Total = transfer.Files.Sum(f => f.Size),
            Files = transfer.Files.Select(f => new ChatFile { Name = f.FileName, Size = f.Size }).ToList(),
        };
        Append(item, transfer.From.Id, transfer.From.Info);
        var answer = new TaskCompletionSource<bool>();
        answers[item.Id] = answer;
        var accepted = await answer.Task;
        if (accepted) incoming = (transfer.From.Id, item.Id);
        return accepted;
    }

    /// <summary>The person's answer to files coming in; <paramref name="always"/> trusts the device from then on.</summary>
    public void Answer(Guid item, bool accept, bool always = false)
    {
        if (!answers.Remove(item, out var answer)) return;
        Update(item, i => i.State = accept ? ChatState.Transferring : ChatState.Declined);
        if (accept && always && state.Conversations.Values.FirstOrDefault(c => c.Items.Any(i => i.Id == item)) is { } conversation &&
            Contact(conversation.Id) is { } contact)
            SetTrusted(contact.Info, true);
        answer.TrySetResult(accept);
    }

    /// <summary>Files on their way in; from a trusted device, their message starts here.</summary>
    private void Accepted(IncomingTransfer transfer)
    {
        if (incoming != null) return;
        var item = new ChatItem
        {
            Sent = false, State = ChatState.Transferring, Total = transfer.Files.Sum(f => f.Size),
            Files = transfer.Files.Select(f => new ChatFile { Name = f.FileName, Size = f.Size }).ToList(),
        };
        Append(item, transfer.From.Id, transfer.From.Info);
        incoming = (transfer.From.Id, item.Id);
    }

    private void Receiving(long done, long total)
    {
        var now = DateTime.UtcNow;
        if (now - lastProgress < TimeSpan.FromMilliseconds(100) && done < total) return;
        lastProgress = now;
        Post(() =>
        {
            if (incoming is not { } current) return;
            Update(current.Item, i =>
            {
                i.State = ChatState.Transferring;
                i.Done = done;
                i.Total = total;
            });
        });
    }

    private void Received(ReceivedTransfer received)
    {
        if (received.Text is { } text)
        {
            Append(new ChatItem { Sent = false, Text = text, State = ChatState.Done }, received.From.Id, received.From.Info);
            return;
        }
        if (incoming is not { } current) return;
        incoming = null;
        Update(current.Item, i =>
        {
            i.State = ChatState.Done;
            i.Done = i.Total;
            // Saved under their own names (photo (1).jpg when there was one already).
            i.Files = received.Files.Select(path => new ChatFile
            {
                Name = Path.GetFileName(path), Path = path, Size = File.Exists(path) ? new System.IO.FileInfo(path).Length : 0,
            }).ToList();
        });
    }

    private void IncomingEnded()
    {
        if (incoming is not { } current) return;
        incoming = null;
        Update(current.Item, i => i.State = ChatState.Failed);
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

    /// <summary>Devices and chats, for the pages' pictures.</summary>
    public void Simulate(IReadOnlyList<Peer> peers, string? open)
    {
        samplePeers = peers;
        selected = open;
        Notify();
    }
}
