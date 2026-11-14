using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoShare.Windows.UI;

/// <summary>Longo Share's pages and menu.</summary>
internal static class SharePages
{
    private static LiveView Live(ShareModule module, Func<FrameworkElement> build) =>
        new(build, refresh => module.Changed += refresh, refresh => module.Changed -= refresh);

    // MARK: - General

    public static FrameworkElement General(ShareModule module) => Live(module, () =>
    {
        var model = module.Model;
        var power = Ui.Card(Ui.Setting(model.IsEnabled ? L("{0} is on", module.Title) : L("{0} is off", module.Title),
            model.IsEnabled ? L("Devices nearby can find this PC and send it files; you can send to them.") : L("Off: this PC can't be found and takes no files."),
            Ui.Switch(model.IsEnabled, on => model.IsEnabled = on), "\uE7E8"));
        var page = Ui.Column(16, Ui.Section(L("Status")), power);
        if (ProblemCard(model) is { } problem) page.Children.Add(problem);

        var name = Dialogs.Field(model.Alias);
        name.Width = 220;
        Commit(name, text => model.Alias = text);
        var folder = Ui.Row(6, Ui.Ghost(L("Change…"), () => PickFolder(model), "\uE8B7"),
                            Ui.IconButton("\uE8A7", () => Pretty.Open(model.Folder), L("Open the folder")));
        page.Children.Add(Ui.Section(L("This PC")));
        page.Children.Add(Ui.Card(Ui.Column(14,
            Ui.Setting(L("Device name"), L("What others see when they look for this PC."), name, "\uE8AC"),
            Ui.Hairline(),
            Ui.Setting(L("Save to"), model.Folder, folder, "\uE896"))));

        var pin = Ui.Row(10);
        if (model.Pin != null)
        {
            var field = Dialogs.Field(model.Pin);
            field.Width = 90;
            Commit(field, text => model.Pin = text);
            pin.Children.Add(field);
        }
        pin.Children.Add(Ui.Switch(model.Pin != null, on => model.Pin = on ? Random.Shared.Next(1000, 10000).ToString() : null));
        page.Children.Add(Ui.Section(L("Receiving")));
        page.Children.Add(Ui.Card(Ui.Column(14,
            Ui.Setting(L("Require a PIN"), L("Senders type it before their files are offered to you."), pin, "\uE72E"),
            Ui.Hairline(),
            Ui.Setting(L("Encryption (HTTPS)"), L("As LocalSend has it. Off is plain HTTP: a little faster, for networks you trust."),
                       Ui.Switch(model.Encrypted, on => model.Encrypted = on), "\uE705"))));
        page.Children.Add(Ui.Text(L("Works with LocalSend on phones, Macs and Linux, on the same Wi-Fi or network."), 11, color: "TextFaint", wrap: true).Margin(2, 0, 0, 0));
        return page;
    });

    private static Border? ProblemCard(ShareModel model)
    {
        if (model.Problem == null) return null;
        var text = L(model.Problem, model.Problem.StartsWith("Port", StringComparison.Ordinal) ? model.Port : model.ProblemDetail);
        var card = Ui.Card(Ui.Row(10, Ui.Glyph("\uE7BA", 16, "Amber"), Ui.Text(text, 12, color: "TextSecondary", wrap: true)));
        card.Res(Border.BorderBrushProperty, "Amber");
        return card;
    }

    /// <summary>A box's text is taken when it's left or Enter is pressed (not at every key).</summary>
    private static void Commit(TextBox box, Action<string> take)
    {
        var start = box.Text;
        void Take()
        {
            if (box.Text != start) take(box.Text);
            start = box.Text;
        }
        box.LostKeyboardFocus += (_, _) => Take();
        box.KeyDown += (_, e) =>
        {
            if (e.Key != Key.Enter) return;
            Take();
            Keyboard.ClearFocus();
        };
    }

    private static void PickFolder(ShareModel model)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = model.Folder, Title = L("Save received files to") };
        if (dialog.ShowDialog() == true) model.Folder = dialog.FolderName;
    }

    // MARK: - Devices

    public static FrameworkElement Devices(ShareModule module) => Live(module, () =>
    {
        var model = module.Model;
        var title = Ui.Text(L("NEARBY DEVICES ({0})", model.Peers.Count), 11, FontWeights.SemiBold, "TextMuted", "MonoFont");
        var look = Ui.Ghost(model.IsScanning ? L("Looking…") : L("Look Again"), () => _ = model.Refresh(), "\uE72C");
        look.IsEnabled = model.IsEnabled && !model.IsScanning;
        var page = Ui.Column(14, Ui.Spread(title, look));
        if (Activity(model) is { } activity) page.Children.Add(activity);
        var list = Ui.Column(8);
        foreach (var peer in model.Peers) list.Children.Add(PeerRow(model, peer, compact: false));
        if (model.Peers.Count == 0) list.Children.Add(Empty(model));
        page.Children.Add(Ui.Card(list, padding: 10));

        var address = Dialogs.Field("");
        address.Width = 200;
        void Add()
        {
            var text = address.Text;
            if (text.Trim().Length > 0) _ = model.Connect(text);
        }
        address.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) Add();
        };
        var add = Ui.Row(8, address, Ui.Ghost(L("Add"), Add, "\uE710"));
        add.IsEnabled = model.IsEnabled;
        page.Children.Add(Ui.Card(Ui.Setting(L("Add by address"), L("Not in the list? Type its IP address, as LocalSend shows it."), add, "\uE968")));

        page.Children.Add(Ui.Section(L("Trusted devices")));
        var trusted = Ui.Column(10);
        foreach (var device in model.Trusted)
        {
            if (trusted.Children.Count > 0) trusted.Children.Add(Ui.Hairline());
            trusted.Children.Add(Ui.Spread(Ui.Row(10, Ui.Glyph("\uE8FB", 13, "Emerald"), Ui.Text(device.Alias, 13, FontWeights.Medium)),
                                           Ui.Ghost(L("Forget"), () => model.Forget(device))));
        }
        if (model.Trusted.Count == 0)
            trusted.Children.Add(Ui.Text(L("None. Turn on Always accept when a device sends you files, and its files come in without asking."), 12, color: "TextMuted", wrap: true));
        page.Children.Add(Ui.Card(trusted));
        page.Children.Add(Ui.Text(L("This PC: {0} · {1}", model.Alias, $"{model.Address}:{model.Port}"), 11, color: "TextFaint", font: "MonoFont").Margin(2, 0, 0, 0));
        return page;
    });

    /// <summary>A device: what it is, and sending to it. Files dropped on it are sent; a click picks some.</summary>
    private static Border PeerRow(ShareModel model, Peer peer, bool compact)
    {
        var info = peer.Info;
        var name = Ui.Row(8, Ui.Text(info.Alias, 13, FontWeights.SemiBold), model.IsTrusted(peer) ? Ui.Chip(L("Trusted"), "Emerald") : null);
        var detail = Ui.Text(string.Join(" · ", new[] { info.DeviceModel, peer.Address }.Where(s => !string.IsNullOrEmpty(s))), 11, color: "TextMuted");
        var busy = model.Current != null;
        UIElement actions = compact
            ? Ui.Row(2, Ui.IconButton("\uE8BD", () => SendText(model, peer), L("Send text")),
                        Ui.IconButton("\uE898", () => PickFiles(model, peer), L("Send files")))
            : Ui.Row(6, Ui.Ghost(L("Text"), () => SendText(model, peer), "\uE8BD"), Ui.Primary(L("Send Files"), () => PickFiles(model, peer), "\uE898"));
        var row = new Border
        {
            Child = Ui.Spread(Ui.Row(12, Pretty.Badge(info, compact ? 32 : 38), Ui.Column(2, name, detail)), actions),
            Padding = new Thickness(10, 8, 10, 8), CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1),
            AllowDrop = !busy, Cursor = busy ? null : Cursors.Hand, Opacity = busy ? 0.55 : 1, IsEnabled = !busy,
            ToolTip = L("Click to pick files, or drop them here"),
        };
        row.Res(Border.BackgroundProperty, "Tint04").Res(Border.BorderBrushProperty, "Hairline");
        void Light(bool on) => row.Res(Border.BorderBrushProperty, on ? "Violet" : "Hairline").Res(Border.BackgroundProperty, on ? "Hover" : "Tint04");
        row.MouseEnter += (_, _) => Light(true);
        row.MouseLeave += (_, _) => Light(false);
        row.MouseLeftButtonUp += (_, _) => PickFiles(model, peer);
        row.DragEnter += (_, e) =>
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            Light(true);
        };
        row.DragLeave += (_, _) => Light(false);
        row.Drop += (_, e) =>
        {
            Light(false);
            if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) _ = model.SendFiles(peer, Expand(paths));
        };
        return row;
    }

    /// <summary>Dropped folders send what's in them.</summary>
    private static IEnumerable<string> Expand(IEnumerable<string> paths) =>
        paths.SelectMany(path => Directory.Exists(path) ? Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories) : new[] { path });

    private static void PickFiles(ShareModel model, Peer peer)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = L("Send to {0}", peer.Info.Alias) };
        if (dialog.ShowDialog() == true) _ = model.SendFiles(peer, dialog.FileNames);
    }

    private static async void SendText(ShareModel model, Peer peer)
    {
        if (await Dialogs.Text(peer) is { Length: > 0 } text) await model.SendText(peer, text);
    }

    private static FrameworkElement Empty(ShareModel model) => Ui.Column(4,
        Ui.Text(!model.IsEnabled ? L("Longo Share is off.") : model.IsScanning ? L("Looking for devices…") : L("No devices found yet."), 13, FontWeights.Medium),
        Ui.Text(L("Open LocalSend or Longo Share on the other device, on the same Wi-Fi."), 11.5, color: "TextMuted", wrap: true)).Margin(6, 6, 6, 6);

    /// <summary>The transfer under way, or how the last one went.</summary>
    private static FrameworkElement? Activity(ShareModel model)
    {
        if (model.Current is { } transfer)
        {
            var fraction = transfer.Total == 0 ? 0 : (double)transfer.Done / transfer.Total;
            var title = transfer.Sending ? L("Sending to {0}", transfer.Device) : transfer.Device.Length > 0 ? L("Receiving from {0}", transfer.Device) : L("Receiving");
            var heading = Ui.Spread(Ui.Row(8, Ui.Glyph(transfer.Sending ? "\uE898" : "\uE896", 13, transfer.Sending ? "Solar" : "Emerald"), Ui.Text(title, 12.5, FontWeights.SemiBold)),
                                    Ui.Ghost(L("Cancel"), model.Cancel));
            var amount = Ui.Text($"{Pretty.Size(transfer.Done)} / {Pretty.Size(transfer.Total)} · {Ui.Percent(fraction)}", 11, color: "TextMuted", font: "MonoFont");
            return Ui.Card(Ui.Column(8, heading, Bar(fraction), amount), padding: 12);
        }
        if (model.Notice is { } notice)
            return Ui.Row(8, Ui.Glyph(notice.Good ? "\uE73E" : "\uE7BA", 12, notice.Good ? "Emerald" : "Amber"),
                          Ui.Text(L(notice.Text, notice.Device), 12, color: "TextSecondary")).Margin(2, 0, 0, 0);
        return null;
    }

    private static Border Bar(double fraction)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Clamp(fraction, 0, 1), GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - Math.Clamp(fraction, 0, 1), GridUnitType.Star) });
        grid.Children.Add(new Border { CornerRadius = new CornerRadius(3) }.Res(Border.BackgroundProperty, "Accent"));
        return new Border { Child = grid, Height = 6, CornerRadius = new CornerRadius(3) }.Res(Border.BackgroundProperty, "Tint10");
    }

    // MARK: - History

    public static FrameworkElement History(ShareModule module) => Live(module, () =>
    {
        var model = module.Model;
        var title = Ui.Text(L("HISTORY ({0})", model.History.Count), 11, FontWeights.SemiBold, "TextMuted", "MonoFont");
        var clear = model.History.Count == 0 ? null : Ui.Ghost(L("Clear"), model.ClearHistory, "\uE74D");
        var list = Ui.Column(0);
        foreach (var item in model.History)
        {
            if (list.Children.Count > 0) list.Children.Add(Ui.Hairline().Margin(0, 10, 0, 10));
            list.Children.Add(HistoryRow(model, item));
        }
        if (model.History.Count == 0) list.Children.Add(Ui.Text(L("Nothing sent or received yet."), 12, color: "TextMuted"));
        var open = Ui.Ghost(L("Open Received Files"), () => Pretty.Open(model.Folder), "\uE8B7");
        open.HorizontalAlignment = HorizontalAlignment.Left;
        return Ui.Column(14, Ui.Spread(title, clear), Ui.Card(list), open);
    });

    private static FrameworkElement HistoryRow(ShareModel model, HistoryItem item)
    {
        var what = item.Text != null ? $"“{Pretty.Shorten(item.Text, 60)}”"
            : item.Files.Count == 0 ? L("Files")
            : item.Files.Count == 1 ? item.Files[0]
            : L("{0} and {1} more", item.Files[0], item.Files.Count - 1);
        var who = item.Sent ? L("To {0}", item.Device) : L("From {0}", item.Device);
        var heading = Ui.Row(12, Ui.Glyph(item.Sent ? "\uE898" : "\uE896", 15, item.Sent ? "Solar" : "Emerald"),
                             Ui.Column(2, Ui.Text(what, 13, FontWeights.Medium), Ui.Text($"{who} · {item.Time:HH:mm, dd/MM}", 11, color: "TextMuted")));
        FrameworkElement? action = item.Text != null
            ? Ui.IconButton("\uE8C8", () => Clipboard.SetText(item.Text), L("Copy"))
            : !item.Sent ? Ui.IconButton("\uE8B7", () => Pretty.Open(model.Folder), L("Open the folder")) : null;
        return Ui.Spread(heading, action);
    }

    // MARK: - Menu

    public static FrameworkElement Menu(ShareModule module) => Live(module, () =>
    {
        var model = module.Model;
        var column = Ui.Column(12);
        if (ProblemCard(model) is { } problem) column.Children.Add(problem);
        if (Activity(model) is { } activity) column.Children.Add(activity);
        var tools = Ui.Row(2, Ui.IconButton("\uE710", async () =>
        {
            if (await Dialogs.Address() is { } address) await model.Connect(address);
        }, L("Add by address")), Ui.IconButton("\uE72C", () => _ = model.Refresh(), L("Look Again")));
        tools.IsEnabled = model.IsEnabled;
        column.Children.Add(Ui.Spread(Ui.Text(model.IsScanning ? L("Looking for devices…") : L("Nearby"), 12, FontWeights.Medium, "TextSecondary"), tools));
        foreach (var peer in model.Peers) column.Children.Add(PeerRow(model, peer, compact: true));
        if (model.Peers.Count == 0) column.Children.Add(Empty(model));
        else column.Children.Add(Ui.Text(L("Drop files on a device to send them, or click it to pick some."), 11, color: "TextFaint", wrap: true));
        column.Children.Add(Ui.Hairline());
        column.Children.Add(Ui.Spread(Ui.Text(L("This PC: {0}", model.Alias), 11.5, color: "TextMuted"),
                                      Ui.IconButton("\uE8B7", () => Pretty.Open(model.Folder), L("Open Received Files"))));
        if (!model.IsEnabled) column.Opacity = 0.5;
        return column;
    });
}

/// <summary>How things are shown: sizes, devices, file kinds.</summary>
internal static class Pretty
{
    public static string Size(long bytes)
    {
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        double value = bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        return unit == 0 ? $"{bytes} B" : $"{value:0.#} {units[unit]}";
    }

    public static string DeviceGlyph(DeviceInfo info) => info.DeviceType switch
    {
        "mobile" => "\uE8EA",
        "tablet" => "\uE70A",
        "web" => "\uE774",
        "headless" or "server" => "\uE968",
        _ => info.DeviceModel is "macOS" or "Windows" or "Linux" ? "\uE7F8" : "\uE7F4",
    };

    /// <summary>A device's glyph on a round tile.</summary>
    public static Border Badge(DeviceInfo info, double size) =>
        new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(size / 2),
            Child = Ui.Glyph(DeviceGlyph(info), size * 0.44, "VioletLight").Centered(),
        }.Res(Border.BackgroundProperty, "Tint10");

    public static string FileGlyph(string type) => type switch
    {
        _ when type.StartsWith("image/", StringComparison.Ordinal) => "\uEB9F",
        _ when type.StartsWith("video/", StringComparison.Ordinal) => "\uE714",
        _ when type.StartsWith("audio/", StringComparison.Ordinal) => "\uE8D6",
        _ when type.StartsWith("text/", StringComparison.Ordinal) => "\uE8A5",
        _ => "\uE7C3",
    };

    public static string Shorten(string text, int length)
    {
        var line = text.ReplaceLineEndings(" ").Trim();
        return line.Length <= length ? line : line[..(length - 1)] + "…";
    }

    /// <summary>A folder, a file or a link, in what Windows opens it with.</summary>
    public static void Open(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // Gone, or nothing opens it.
        }
    }

    private static TextBlock Centered(this TextBlock text)
    {
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.VerticalAlignment = VerticalAlignment.Center;
        return text;
    }
}
