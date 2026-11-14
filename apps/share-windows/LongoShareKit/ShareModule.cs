using System.Windows;
using LongoKit.UI;
using LongoShare.Windows.UI;

namespace LongoShare.Windows;

/// <summary>Longo Share as a module: on its own (LongoShare.exe) or in LongoKit.</summary>
public sealed class ShareModule : ILongoModule, ISampleData
{
    private ShareModel model = new(new ShareState());

    public ShareModel Model => model;
    /// <summary>For the pages' pictures: a window drawn in place of the General page.</summary>
    internal Func<FrameworkElement>? Preview { get; private set; }

    public string Id => "share";
    public string Title => "Longo Share";
    public string Blurb => "Files between your devices, nearby";
    public string IconName => "share.ico";
    public bool IsOn => model.IsEnabled;
    public event Action? Changed;
    public event Action<int>? OpenTab { add { } remove { } }

    public ShareModule() => Localizer.Register(Strings.Vietnamese);

    public string Status => !model.IsEnabled ? ""
        : model.Current is { } transfer ? Ui.Percent(transfer.Total == 0 ? 0 : (double)transfer.Done / transfer.Total)
        : model.Peers.Count == 1 ? Localizer.L("1 device") : Localizer.L("{0} devices", model.Peers.Count);

    public void SetOn(bool on) => model.IsEnabled = on;

    public void Start()
    {
        var next = new ShareModel();
        Use(next);
        model.Ask = transfer => Dialogs.Incoming(transfer, () => next.SetTrusted(transfer.From, true));
        model.AskPin = Dialogs.Pin;
        model.ShowMessage = Dialogs.Message;
        model.Start();
    }

    public void Stop() => model.Stop();

    public void UseSampleData()
    {
        var state = new ShareState { Alias = "Long's PC", Folder = @"C:\Users\Long\Downloads", Pin = null };
        state.Trusted.Add(new TrustedDevice { Fingerprint = "a1", Alias = "MacBook Air" });
        state.History.Add(new HistoryItem { Sent = false, Device = "Pixel 8", Time = new DateTime(2026, 11, 14, 9, 41, 0), Files = { "IMG_2041.jpg", "IMG_2042.jpg", "IMG_2043.jpg" } });
        state.History.Add(new HistoryItem { Sent = true, Device = "MacBook Air", Time = new DateTime(2026, 11, 14, 9, 12, 0), Files = { "Báo cáo quý 3.pdf" } });
        state.History.Add(new HistoryItem { Sent = false, Device = "iPad", Time = new DateTime(2026, 11, 13, 21, 5, 0), Text = "https://longokit.vercel.app" });
        Use(new ShareModel(state));
        model.Simulate(SamplePeers, new Transfer("Pixel 8", false, 38_400_000, 61_200_000), new Notice("Sent to {0}.", "MacBook Air"));
    }

    private static readonly Peer[] SamplePeers =
    {
        new(new DeviceInfo { Alias = "MacBook Air", DeviceModel = "macOS", DeviceType = "desktop", Fingerprint = "a1" }, "192.168.1.24"),
        new(new DeviceInfo { Alias = "Pixel 8", DeviceModel = "Google", DeviceType = "mobile", Fingerprint = "b2" }, "192.168.1.31"),
        new(new DeviceInfo { Alias = "iPad", DeviceModel = "iPad", DeviceType = "tablet", Fingerprint = "c3" }, "192.168.1.40"),
    };

    public IReadOnlyList<(string Name, int Tab, Action Open)> SamplePages => new (string, int, Action)[]
    {
        ("incoming", 0, () => Preview = () => Dialogs.IncomingView(new IncomingTransfer(SamplePeers[1], new[]
        {
            new FileInfo { Id = "1", FileName = "IMG_2044.jpg", Size = 3_480_000, FileType = "image/jpeg" },
            new FileInfo { Id = "2", FileName = "IMG_2045.jpg", Size = 2_910_000, FileType = "image/jpeg" },
            new FileInfo { Id = "3", FileName = "Ghi âm 14-11.m4a", Size = 812_000, FileType = "audio/mp4" },
        }), (_, _) => { })),
        ("message", 0, () => Preview = () => Dialogs.MessageView(SamplePeers[2], "Gửi bạn link nè: https://longokit.vercel.app", () => { })),
        // The last one puts the General page back, for the next pictures.
        ("devices", 1, () => Preview = null),
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
        new ModuleTab(Localizer.L("General"), "\uE713", () => Preview?.Invoke() ?? SharePages.General(this)),
        new ModuleTab(Localizer.L("Devices"), "\uE8EA", () => SharePages.Devices(this)),
        new ModuleTab(Localizer.L("History"), "\uE81C", () => SharePages.History(this)),
    };

    public FrameworkElement CreateMenu() => SharePages.Menu(this);
}
