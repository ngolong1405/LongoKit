using System.Windows;
using LongoKit.UI;
using LongoShare.Windows.UI;

namespace LongoShare.Windows;

/// <summary>Longo Share as a module: on its own (LongoShare.exe) or in LongoKit.</summary>
public sealed class ShareModule : ILongoModule, ISampleData
{
    private ShareModel model = new(new ShareState());
    /// <summary>What's typed in each chat and not sent yet (pages are built again as things change).</summary>
    private readonly Dictionary<string, string> drafts = new();

    public ShareModel Model => model;

    public string Id => "share";
    public string Title => "Longo Share";
    public string Blurb => "Files between your devices, nearby";
    public string IconName => "share.ico";
    public bool IsOn => model.IsEnabled;
    public event Action? Changed;
    public event Action<int>? OpenTab;

    public ShareModule() => Localizer.Register(Strings.Vietnamese);

    public string Status => !model.IsEnabled ? ""
        : model.Current is { } transfer ? Ui.Percent(transfer.Total == 0 ? 0 : (double)transfer.Done / transfer.Total)
        : model.Peers.Count == 1 ? Localizer.L("1 device") : Localizer.L("{0} devices", model.Peers.Count);

    public void SetOn(bool on) => model.IsEnabled = on;

    public void Start()
    {
        var next = new ShareModel();
        // Something came in: the window comes up on its chat.
        next.WantsWindow += id =>
        {
            next.Selected = id;
            OpenTab?.Invoke(0);
        };
        Use(next);
        model.Start();
    }

    public void Stop()
    {
        model.Stop();
        model.SaveNow();
    }

    /// <summary>Opens the window on a device's chat (from the menu).</summary>
    public void ShowChat(string id)
    {
        model.Selected = id;
        OpenTab?.Invoke(0);
    }

    public string Draft(string id) => drafts.GetValueOrDefault(id, "");
    public void SetDraft(string id, string text) => drafts[id] = text;

    public void UseSampleData()
    {
        var state = new ShareState { Alias = "Long's PC", Folder = @"C:\Users\Long\Downloads\Longo Share", Pin = null };
        state.Trusted.Add(new TrustedDevice { Fingerprint = "a1", Alias = "MacBook Air" });
        var day = new DateTime(2026, 11, 14, 14, 6, 0);
        state.Conversations["b2"] = new Conversation
        {
            Id = "b2", Alias = "Pixel 8", DeviceModel = "Google", DeviceType = "mobile",
            Items =
            {
                new ChatItem { Sent = false, Text = "Gửi mình mấy tấm hình hôm qua nha", State = ChatState.Done, Time = day },
                new ChatItem
                {
                    Sent = true, State = ChatState.Done, Time = day.AddMinutes(2), Done = 6_390_000, Total = 6_390_000,
                    Files = { new ChatFile { Name = "IMG_2041.jpg", Size = 3_480_000 }, new ChatFile { Name = "IMG_2042.jpg", Size = 2_910_000 } },
                },
                new ChatItem { Sent = true, Text = "Xong rồi đó. Link bài viết: https://longokit.vercel.app/share", State = ChatState.Done, Time = day.AddMinutes(3) },
                new ChatItem
                {
                    Sent = false, State = ChatState.Asking, Time = day.AddMinutes(5), Total = 2_052_000,
                    Files = { new ChatFile { Name = "Ghi âm 14-11.m4a", Size = 812_000 }, new ChatFile { Name = "Báo cáo quý 3.pdf", Size = 1_240_000 } },
                },
                new ChatItem
                {
                    Sent = true, State = ChatState.Transferring, Time = day.AddMinutes(6), Done = 38_400_000, Total = 61_200_000,
                    Files = { new ChatFile { Name = "video-4k.mp4", Size = 61_200_000 } },
                },
            },
        };
        state.Conversations["c3"] = new Conversation
        {
            Id = "c3", Alias = "iPad", DeviceModel = "iPad", DeviceType = "tablet", Unread = 2,
            Items = { new ChatItem { Sent = false, Text = "https://longokit.vercel.app", State = ChatState.Done, Time = day.AddHours(-15) } },
        };
        state.Conversations["d4"] = new Conversation
        {
            Id = "d4", Alias = "Logan's MacBook Air", DeviceModel = "macOS", DeviceType = "desktop",
            Items = { new ChatItem { Sent = false, Text = "tôi sẽ xem", State = ChatState.Done, Time = day.AddDays(-2) } },
        };
        Use(new ShareModel(state));
        model.Simulate(SamplePeers, "b2");
    }

    private static readonly Peer[] SamplePeers =
    {
        new(new DeviceInfo { Alias = "MacBook Air", DeviceModel = "macOS", DeviceType = "desktop", Fingerprint = "a1" }, "192.168.1.24"),
        new(new DeviceInfo { Alias = "Pixel 8", DeviceModel = "Google", DeviceType = "mobile", Fingerprint = "b2" }, "192.168.1.31"),
        new(new DeviceInfo { Alias = "iPad", DeviceModel = "iPad", DeviceType = "tablet", Fingerprint = "c3" }, "192.168.1.40"),
    };

    public IReadOnlyList<(string Name, int Tab, Action Open)> SamplePages => new (string, int, Action)[]
    {
        ("offline", 0, () => model.Selected = "d4"),
        // The last one puts the first chat back, for the next pictures.
        ("chat", 0, () => model.Selected = "b2"),
    };

    private void Use(ShareModel next)
    {
        model.Changed -= OnChanged;
        model = next;
        model.Changed += OnChanged;
        OnChanged();
    }

    private void OnChanged() => Changed?.Invoke();

    public IReadOnlyList<ModuleTab> Tabs => new[]
    {
        new ModuleTab(Localizer.L("Devices"), "\uE8BD", () => SharePages.Devices(this), Fill: true),
        new ModuleTab(Localizer.L("General"), "\uE713", () => SharePages.General(this)),
    };

    public FrameworkElement CreateMenu() => SharePages.Menu(this);
}
