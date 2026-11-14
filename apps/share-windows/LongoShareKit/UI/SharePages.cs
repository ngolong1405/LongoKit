using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoShare.Windows.UI;

/// <summary>Longo Share's pages and menu: the devices and a chat with each, General, and the notification area menu.</summary>
internal static class SharePages
{
    private static LiveView Live(ShareModule module, Func<FrameworkElement> build) =>
        new(build, refresh => module.Changed += refresh, refresh => module.Changed -= refresh);

    // MARK: - Devices: the list and a chat

    public static FrameworkElement Devices(ShareModule module)
    {
        var view = Live(module, () =>
        {
            var model = module.Model;
            var grid = new Grid { MinHeight = 560 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var list = new Border { Child = DeviceList(module), BorderThickness = new Thickness(0, 0, 1, 0) }.Res(Border.BorderBrushProperty, "Hairline");
            grid.Children.Add(list);
            FrameworkElement chat = model.Contact(model.Selected) is { } contact ? Chat(module, contact) : NoChat(model);
            Grid.SetColumn(chat, 1);
            grid.Children.Add(chat);
            return grid;
        });
        // Messages in the chat on screen are read at once; otherwise the window comes up on them.
        view.IsVisibleChanged += (_, _) => module.Model.ChatOnScreen = view.IsVisible;
        return view;
    }

    private static FrameworkElement DeviceList(ShareModule module)
    {
        var model = module.Model;
        var look = Ui.IconButton("\uE72C", () => _ = model.Refresh(), L("Look Again"));
        look.IsEnabled = model.IsEnabled && !model.IsScanning;
        var header = Ui.Spread(Ui.Text(model.IsScanning ? L("LOOKING…") : L("DEVICES"), 11, FontWeights.SemiBold, "TextMuted", "MonoFont"), look)
            .Margin(14, 10, 8, 6);
        var rows = Ui.Column(2);
        foreach (var contact in model.Contacts) rows.Children.Add(DeviceRow(module, contact));
        if (model.Contacts.Count == 0) rows.Children.Add(Empty(model));
        var scroll = Ui.Scroll(new Border { Child = rows, Padding = new Thickness(8, 0, 8, 8) });

        var address = Dialogs.Field("");
        address.ToolTip = L("Add by IP address");
        var placeholder = Ui.Text(L("Add by IP address"), 12.5, color: "TextFaint").Margin(10, 0, 0, 0);
        placeholder.VerticalAlignment = VerticalAlignment.Center;
        placeholder.IsHitTestVisible = false;
        address.TextChanged += (_, _) => placeholder.Visibility = address.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        address.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && address.Text.Trim().Length > 0) _ = model.Connect(address.Text);
        };
        var box = new Grid { Children = { address, placeholder } };
        var bottom = Ui.Column(6, box);
        if (model.LastAddressFailed is { } failed) bottom.Children.Add(Ui.Text(L("Nothing answered at {0}.", failed), 11, color: "Amber"));
        bottom.IsEnabled = model.IsEnabled;
        var footer = new Border { Child = bottom, Padding = new Thickness(10), BorderThickness = new Thickness(0, 1, 0, 0) }.Res(Border.BorderBrushProperty, "Hairline");

        var dock = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        dock.Children.Add(header);
        dock.Children.Add(footer);
        dock.Children.Add(scroll);
        return dock;
    }

    private static Border DeviceRow(ShareModule module, Contact contact)
    {
        var model = module.Model;
        var selected = model.Selected == contact.Id;
        var badge = new Grid { Children = { Pretty.Badge(contact.Info, 34) } };
        var dot = new Border
        {
            Width = 10, Height = 10, CornerRadius = new CornerRadius(5), BorderThickness = new Thickness(2),
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
        }.Res(Border.BackgroundProperty, contact.IsOnline ? "Emerald" : "TextFaint").Res(Border.BorderBrushProperty, "Canvas");
        badge.Children.Add(dot);
        badge.Opacity = contact.IsOnline ? 1 : 0.6;
        var subtitle = contact.Conversation?.Items.LastOrDefault() is { } last ? Words.Line(last)
            : contact.IsOnline ? contact.Info.DeviceModel ?? "" : L("Not nearby");
        var text = Ui.Column(2, Ui.Text(contact.Info.Alias, 13, FontWeights.SemiBold), Ui.Text(subtitle, 11, color: "TextMuted"));
        foreach (var line in text.Children.OfType<TextBlock>()) line.TextTrimming = TextTrimming.CharacterEllipsis;
        UIElement? unread = contact.Conversation is { Unread: > 0 } c
            ? new Border { Child = Ui.Text(c.Unread.ToString(), 10, FontWeights.Bold, "White", "MonoFont"), Padding = new Thickness(6, 1, 6, 1), CornerRadius = new CornerRadius(9) }
                .Res(Border.BackgroundProperty, "Solar")
            : null;
        var row = new Border
        {
            Child = Ui.Spread(Ui.Row(10, badge, text), unread),
            Padding = new Thickness(8, 7, 8, 7), CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1),
            Cursor = Cursors.Hand, AllowDrop = contact.IsOnline,
        };
        void Light(bool hover, bool drop = false) =>
            row.Res(Border.BackgroundProperty, selected ? "Hover" : hover ? "Tint04" : "Transparent").Res(Border.BorderBrushProperty, drop ? "Violet" : "Transparent");
        Light(false);
        row.MouseEnter += (_, _) => Light(true);
        row.MouseLeave += (_, _) => Light(false);
        row.MouseLeftButtonUp += (_, _) => model.Selected = contact.Id;
        DropFiles(row, contact, model, on => Light(on, on));
        return row;
    }

    private static FrameworkElement NoChat(ShareModel model)
    {
        var column = Ui.Column(10,
            Ui.Glyph("\uE8F2", 30, "TextFaint"),
            Ui.Text(model.Contacts.Count == 0 ? L("No devices yet") : L("Pick a device"), 15, FontWeights.SemiBold, font: "DisplayFont"),
            Ui.Text(L("Open LocalSend or Longo Share on the other device, on the same Wi-Fi."), 12, color: "TextMuted", wrap: true));
        foreach (var child in column.Children.OfType<FrameworkElement>()) child.HorizontalAlignment = HorizontalAlignment.Center;
        ((TextBlock)column.Children[2]).TextAlignment = TextAlignment.Center;
        if (ProblemCard(model) is { } problem) column.Children.Add(problem);
        column.MaxWidth = 340;
        column.VerticalAlignment = VerticalAlignment.Center;
        column.HorizontalAlignment = HorizontalAlignment.Center;
        return column;
    }

    private static FrameworkElement Chat(ShareModule module, Contact contact)
    {
        var model = module.Model;
        var items = contact.Conversation?.Items ?? new List<ChatItem>();

        // Header: who, where, Always accept, clear.
        var who = Ui.Row(10, Pretty.Badge(contact.Info, 32),
            Ui.Column(1, Ui.Text(contact.Info.Alias, 14, FontWeights.SemiBold),
                         Ui.Text(contact.Peer is { } peer ? string.Join(" · ", new[] { contact.Info.DeviceModel, peer.Address }.Where(s => !string.IsNullOrEmpty(s)))
                                                          : L("Not nearby"), 11, color: contact.IsOnline ? "TextMuted" : "Amber")));
        var tools = Ui.Row(6);
        if (!string.IsNullOrEmpty(contact.Info.Fingerprint))
        {
            var trusted = model.IsTrusted(contact.Info);
            var always = Ui.Ghost(L("Always accept"), () => model.SetTrusted(contact.Info, !trusted), trusted ? "\uE8FB" : "\uE83D")
                .Tip(trusted ? L("Files from this device come in without asking. Click to ask again.") : L("Take files from this device without asking."));
            if (trusted) always.Opacity = 1;
            tools.Children.Add(always);
        }
        if (items.Count > 0) tools.Children.Add(Ui.IconButton("\uE74D", () => model.Clear(contact.Id), L("Clear this chat")));
        var header = new Border { Child = Ui.Spread(who, tools), Padding = new Thickness(16, 10, 12, 10), BorderThickness = new Thickness(0, 0, 0, 1) }
            .Res(Border.BorderBrushProperty, "Hairline");

        // Messages.
        var messages = Ui.Column(12);
        if (items.Count == 0)
        {
            var hint = Ui.Text(contact.IsOnline ? L("Drop files here, or type a message, to send them to {0}.", contact.Info.Alias)
                                                : L("{0} isn't on this network now.", contact.Info.Alias), 12, color: "TextMuted", wrap: true);
            hint.TextAlignment = TextAlignment.Center;
            hint.Margin = new Thickness(40, 120, 40, 0);
            messages.Children.Add(hint);
        }
        foreach (var item in items) messages.Children.Add(Bubble(module, contact, item));
        var scroll = Ui.Scroll(new Border { Child = messages, Padding = new Thickness(16) });
        // The newest at the bottom, in view.
        scroll.Loaded += (_, _) => scroll.ScrollToEnd();

        // Composer: attach, the message, send.
        var draft = Dialogs.Field(module.Draft(contact.Id), multiline: false);
        draft.AcceptsReturn = false;
        draft.TextWrapping = TextWrapping.Wrap;
        draft.MaxHeight = 110;
        draft.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        var placeholder = Ui.Text(L("Message {0}", contact.Info.Alias), 13, color: "TextFaint").Margin(10, 0, 0, 0);
        placeholder.VerticalAlignment = VerticalAlignment.Center;
        placeholder.IsHitTestVisible = false;
        placeholder.Visibility = draft.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        void Send()
        {
            if (contact.Peer is not { } to || draft.Text.Trim().Length == 0) return;
            var text = draft.Text;
            draft.Text = "";
            module.SetDraft(contact.Id, "");
            model.SendText(to, text);
        }
        draft.TextChanged += (_, _) =>
        {
            module.SetDraft(contact.Id, draft.Text);
            placeholder.Visibility = draft.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        };
        // Enter sends; Shift+Enter starts a new line.
        draft.PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Key.Enter) return;
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
            {
                var at = draft.CaretIndex;
                draft.Text = draft.Text.Insert(at, Environment.NewLine);
                draft.CaretIndex = at + Environment.NewLine.Length;
            }
            else
            {
                Send();
            }
            e.Handled = true;
        };
        var field = new Grid { Children = { draft, placeholder } };
        var attach = Ui.IconButton("\uE723", () => { if (contact.Peer is { } to) PickFiles(model, to); }, L("Send files"));
        var send = Ui.Primary("", Send, "\uE724").Tip(L("Send"));
        var composerGrid = new Grid();
        composerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        composerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        composerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(field, 1);
        Grid.SetColumn(send, 2);
        attach.Margin = new Thickness(0, 0, 8, 0);
        send.Margin = new Thickness(8, 0, 0, 0);
        composerGrid.Children.Add(attach);
        composerGrid.Children.Add(field);
        composerGrid.Children.Add(send);
        composerGrid.IsEnabled = contact.IsOnline && model.IsEnabled;
        composerGrid.Opacity = contact.IsOnline ? 1 : 0.5;
        var composer = new Border { Child = composerGrid, Padding = new Thickness(12, 10, 12, 10), BorderThickness = new Thickness(0, 1, 0, 0) }
            .Res(Border.BorderBrushProperty, "Hairline");

        var dock = new DockPanel { AllowDrop = contact.IsOnline };
        DockPanel.SetDock(header, Dock.Top);
        DockPanel.SetDock(composer, Dock.Bottom);
        dock.Children.Add(header);
        dock.Children.Add(composer);
        dock.Children.Add(scroll);
        var frame = new Border { Child = dock, BorderThickness = new Thickness(2), Background = Brushes.Transparent }.Res(Border.BorderBrushProperty, "Transparent");
        frame.AllowDrop = contact.IsOnline;
        DropFiles(frame, contact, model, on => frame.Res(Border.BorderBrushProperty, on ? "Violet" : "Transparent"));
        return frame;
    }

    /// <summary>Files dropped from Explorer go to <paramref name="contact"/>; <paramref name="light"/> shows where.</summary>
    private static void DropFiles(FrameworkElement target, Contact contact, ShareModel model, Action<bool> light)
    {
        if (!contact.IsOnline) return;
        target.DragEnter += (_, e) =>
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            light(true);
            e.Handled = true;
        };
        target.DragOver += (_, e) =>
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            e.Handled = true;
        };
        target.DragLeave += (_, _) => light(false);
        target.Drop += (_, e) =>
        {
            light(false);
            if (e.Data.GetData(DataFormats.FileDrop) is string[] paths && contact.Peer is { } peer) model.SendFiles(peer, Expand(paths));
            e.Handled = true;
        };
    }

    // MARK: - A message

    private static FrameworkElement Bubble(ShareModule module, Contact contact, ChatItem item)
    {
        var model = module.Model;
        FrameworkElement body = item.Text is { } text ? TextBubble(item, text) : FilesBubble(model, contact, item);
        var time = Ui.Text(item.Time.Date == DateTime.Today ? item.Time.ToString("HH:mm") : item.Time.ToString("dd/MM HH:mm"), 10, color: "TextFaint");
        var footer = Ui.Row(6, time);
        if (item.Text is { } copy && !item.Sent)
        {
            var hyperlink = new Hyperlink(new Run(L("Copy"))) { TextDecorations = null };
            hyperlink.Click += (_, _) => Clipboard.SetText(copy);
            hyperlink.SetResourceReference(TextElement.ForegroundProperty, "VioletLight");
            var link = new TextBlock(hyperlink) { FontSize = 10 };
            footer.Children.Add(link);
        }
        if (item.Text != null && item.Sent)
        {
            footer.Children.Add(Ui.Glyph(Words.Glyph(item.State), 10, Words.Color(item.State)));
            if (item.State is ChatState.Declined or ChatState.Failed) footer.Children.Add(Ui.Text(Words.Status(item, contact.Info.Alias), 10, color: "Amber"));
        }
        footer.Margin = new Thickness(4, 0, 4, 0);
        var column = Ui.Column(4, body, footer);
        column.HorizontalAlignment = item.Sent ? HorizontalAlignment.Right : HorizontalAlignment.Left;
        foreach (var child in column.Children.OfType<FrameworkElement>()) child.HorizontalAlignment = column.HorizontalAlignment;
        column.MaxWidth = 380;
        return column;
    }

    private static FrameworkElement TextBubble(ChatItem item, string text)
    {
        var block = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 13 }.Res(TextBlock.FontFamilyProperty, "UIFont")
            .Res(TextBlock.ForegroundProperty, item.Sent ? "White" : "Text");
        foreach (var inline in Words.Linked(text, item.Sent)) block.Inlines.Add(inline);
        var bubble = new Border { Child = block, Padding = new Thickness(12, 8, 12, 8), CornerRadius = new CornerRadius(16) }
            .Res(Border.BackgroundProperty, item.Sent ? "AccentDiagonal" : "Tint10");
        if (item.State is ChatState.Failed or ChatState.Declined) bubble.Opacity = 0.6;
        var menu = new ContextMenu();
        var copy = new MenuItem { Header = L("Copy") };
        copy.Click += (_, _) => Clipboard.SetText(text);
        menu.Items.Add(copy);
        bubble.ContextMenu = menu;
        return bubble;
    }

    private static FrameworkElement FilesBubble(ShareModel model, Contact contact, ChatItem item)
    {
        var column = Ui.Column(10);
        // One picture on this PC: shown big.
        if (item.Files.Count == 1 && item.Files[0].Path is { } single && Thumbnails.IsPicture(single) && Thumbnails.Image(single, 300) is { } big)
        {
            var image = new Image { Source = big, MaxWidth = 300, MaxHeight = 220, Stretch = Stretch.Uniform, Cursor = Cursors.Hand };
            image.MouseLeftButtonUp += (_, _) => Pretty.Open(single);
            column.Children.Add(new Border { Child = image, CornerRadius = new CornerRadius(10), ClipToBounds = true, HorizontalAlignment = HorizontalAlignment.Left });
        }
        var list = Ui.Column(6);
        var bigShown = column.Children.Count > 0;
        foreach (var file in item.Files.Take(5))
        {
            UIElement icon = !bigShown && file.Path is { } path && Thumbnails.IsPicture(path) && Thumbnails.Image(path, 60) is { } small
                ? new Border { Child = new Image { Source = small, Width = 30, Height = 30, Stretch = Stretch.UniformToFill }, CornerRadius = new CornerRadius(6), ClipToBounds = true }
                : Ui.Glyph(Pretty.FileGlyph(file.Name), 13, "VioletLight");
            var name = Ui.Text(file.Name, 12.5);
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            name.MaxWidth = 200;
            var row = Ui.Spread(Ui.Row(8, icon, name), Ui.Text(Pretty.Size(file.Size), 10.5, color: "TextMuted", font: "MonoFont"));
            if (item.State == ChatState.Done && file.Path is { } open)
            {
                row.Cursor = Cursors.Hand;
                row.Background = Brushes.Transparent;
                row.MouseLeftButtonUp += (_, e) => { if (e.ClickCount == 1) Pretty.Open(open); };
            }
            list.Children.Add(row);
        }
        if (item.Files.Count > 5) list.Children.Add(Ui.Text(L("and {0} more", item.Files.Count - 5), 11, color: "TextMuted"));
        column.Children.Add(list);
        if (item.State == ChatState.Transferring) column.Children.Add(Bar(item.Fraction));

        UIElement? action = item.State switch
        {
            ChatState.Transferring or ChatState.Waiting => Ui.Ghost(L("Cancel"), () => model.Cancel(item.Id)),
            ChatState.Done when !item.Sent => Ui.Ghost(L("Show in Explorer"), () => Reveal(item, model), "\uE8B7"),
            _ => null,
        };
        column.Children.Add(Ui.Spread(Ui.Row(6, Ui.Glyph(Words.Glyph(item.State), 11, Words.Color(item.State)),
                                             Ui.Text(Words.Status(item, contact.Info.Alias), 11, color: "TextMuted")), action));

        if (item.State == ChatState.Asking)
        {
            var always = false;
            var check = new CheckBox { Content = Ui.Text(L("Always accept from {0}", contact.Info.Alias), 11.5, color: "TextSecondary"), VerticalContentAlignment = VerticalAlignment.Center };
            check.Click += (_, _) => always = check.IsChecked == true;
            var buttons = Ui.Row(8, Ui.Ghost(L("Decline"), () => model.Answer(item.Id, false)),
                                    Ui.Primary(L("Accept"), () => model.Answer(item.Id, true, always), "\uE896"));
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            column.Children.Add(Ui.Hairline());
            column.Children.Add(check);
            column.Children.Add(buttons);
        }
        if (item.State == ChatState.Pin)
        {
            var pin = Dialogs.Field("");
            pin.Width = 100;
            pin.KeyDown += (_, e) => { if (e.Key == Key.Enter) model.AnswerPin(item.Id, pin.Text); };
            column.Children.Add(Ui.Hairline());
            column.Children.Add(Ui.Text(L("{0} asks for a PIN. It's shown on that device.", contact.Info.Alias), 11.5, color: "TextSecondary", wrap: true));
            column.Children.Add(Ui.Spread(pin, Ui.Row(8, Ui.Ghost(L("Cancel"), () => model.AnswerPin(item.Id, null)),
                                                        Ui.Primary(L("Send"), () => model.AnswerPin(item.Id, pin.Text)))));
        }
        var card = new Border { Child = column, Padding = new Thickness(12), CornerRadius = new CornerRadius(16), BorderThickness = new Thickness(1), Width = 330 }
            .Res(Border.BackgroundProperty, "Island")
            .Res(Border.BorderBrushProperty, item.State is ChatState.Asking or ChatState.Pin ? "Violet" : item.Sent ? "SolarLight" : "Hairline");
        return card;
    }

    private static void Reveal(ChatItem item, ShareModel model)
    {
        var first = item.Files.Select(f => f.Path).FirstOrDefault(File.Exists);
        if (first != null) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{first}\"") { UseShellExecute = true });
        else Pretty.Open(model.Folder);
    }

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
        // The folder's path opens it; Change picks another.
        var path = new TextBlock(new Hyperlink(new Run(model.Folder))) { FontSize = 11.5, MaxWidth = 300, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center }
            .Res(TextBlock.FontFamilyProperty, "MonoFont").Tip(L("Open the folder"));
        var hyperlink = (Hyperlink)path.Inlines.FirstInline;
        hyperlink.SetResourceReference(TextElement.ForegroundProperty, "TextSecondary");
        hyperlink.TextDecorations = null;
        hyperlink.Click += (_, _) => Pretty.Open(model.Folder);
        var folder = Ui.Row(10, path, Ui.Ghost(L("Change…"), () => PickFolder(model), "\uE8B7"));
        page.Children.Add(Ui.Section(L("This PC")));
        page.Children.Add(Ui.Card(Ui.Column(14,
            Ui.Setting(L("Device name"), L("What others see when they look for this PC."), name, "\uE8AC"),
            Ui.Hairline(),
            Ui.Setting(L("Save to"), null, folder, "\uE896"))));

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

        page.Children.Add(Ui.Section(L("Trusted devices")));
        var trusted = Ui.Column(10);
        foreach (var device in model.Trusted)
        {
            if (trusted.Children.Count > 0) trusted.Children.Add(Ui.Hairline());
            trusted.Children.Add(Ui.Spread(Ui.Row(10, Ui.Glyph("\uE8FB", 13, "Emerald"), Ui.Text(device.Alias, 13, FontWeights.Medium)),
                                           Ui.Ghost(L("Forget"), () => model.Forget(device))));
        }
        if (model.Trusted.Count == 0)
            trusted.Children.Add(Ui.Text(L("None yet. Turn on Always accept in a device's chat, and its files come in without asking."), 12, color: "TextMuted", wrap: true));
        page.Children.Add(Ui.Card(trusted));
        page.Children.Add(Ui.Text(L("This PC: {0} · {1}", model.Alias, $"{model.Address}:{model.Port}"), 11, color: "TextFaint", font: "MonoFont").Margin(2, 0, 0, 0));
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

    // MARK: - Menu

    public static FrameworkElement Menu(ShareModule module) => Live(module, () =>
    {
        var model = module.Model;
        var column = Ui.Column(10);
        if (ProblemCard(model) is { } problem) column.Children.Add(problem);
        if (model.Current is { } transfer)
            column.Children.Add(Ui.Card(Ui.Column(6,
                Ui.Text(transfer.Sending ? L("Sending to {0}", transfer.Device) : L("Receiving from {0}", transfer.Device), 12, FontWeights.SemiBold),
                Bar(transfer.Total == 0 ? 0 : (double)transfer.Done / transfer.Total)), padding: 10));
        var look = Ui.IconButton("\uE72C", () => _ = model.Refresh(), L("Look Again"));
        column.Children.Add(Ui.Spread(Ui.Text(model.IsScanning ? L("Looking for devices…") : L("Nearby"), 12, FontWeights.Medium, "TextSecondary"), look));
        foreach (var contact in model.Contacts.Where(c => c.IsOnline || c.Conversation is { Unread: > 0 }))
            column.Children.Add(MenuRow(module, contact));
        if (model.Peers.Count == 0) column.Children.Add(Empty(model));
        column.Children.Add(Ui.Hairline());
        column.Children.Add(Ui.Spread(Ui.Text(L("This PC: {0}", model.Alias), 11.5, color: "TextMuted"),
                                      Ui.IconButton("\uE8B7", () => Pretty.Open(model.Folder), L("Open Received Files"))));
        if (!model.IsEnabled) column.Opacity = 0.5;
        return column;
    });

    private static Border MenuRow(ShareModule module, Contact contact)
    {
        var model = module.Model;
        var subtitle = contact.Conversation?.Items.LastOrDefault() is { } last ? Words.Line(last) : contact.Info.DeviceModel ?? "";
        var text = Ui.Column(1, Ui.Text(contact.Info.Alias, 12.5, FontWeights.SemiBold), Ui.Text(subtitle, 11, color: "TextMuted"));
        foreach (var line in text.Children.OfType<TextBlock>()) line.TextTrimming = TextTrimming.CharacterEllipsis;
        var trailing = Ui.Row(4);
        if (contact.Conversation is { Unread: > 0 } c)
            trailing.Children.Add(new Border { Child = Ui.Text(c.Unread.ToString(), 10, FontWeights.Bold, "White", "MonoFont"), Padding = new Thickness(6, 1, 6, 1), CornerRadius = new CornerRadius(9), VerticalAlignment = VerticalAlignment.Center }
                .Res(Border.BackgroundProperty, "Solar"));
        if (contact.Peer is { } peer) trailing.Children.Add(Ui.IconButton("\uE723", () => PickFiles(model, peer), L("Send files")));
        var row = new Border
        {
            Child = Ui.Spread(Ui.Row(10, Pretty.Badge(contact.Info, 30), text), trailing),
            Padding = new Thickness(8, 6, 8, 6), CornerRadius = new CornerRadius(10), Cursor = Cursors.Hand,
            ToolTip = L("Open the chat"), AllowDrop = contact.IsOnline,
        };
        row.Res(Border.BackgroundProperty, "Tint04").Res(Border.BorderBrushProperty, "Transparent");
        row.BorderThickness = new Thickness(1);
        row.MouseEnter += (_, _) => row.Res(Border.BackgroundProperty, "Hover");
        row.MouseLeave += (_, _) => row.Res(Border.BackgroundProperty, "Tint04");
        row.MouseLeftButtonUp += (_, _) => module.ShowChat(contact.Id);
        DropFiles(row, contact, model, on => row.Res(Border.BorderBrushProperty, on ? "Violet" : "Transparent"));
        return row;
    }

    // MARK: - Pieces

    /// <summary>Dropped folders send what's in them.</summary>
    private static IEnumerable<string> Expand(IEnumerable<string> paths) =>
        paths.SelectMany(path => Directory.Exists(path) ? Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories) : new[] { path });

    private static void PickFiles(ShareModel model, Peer peer)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = L("Send to {0}", peer.Info.Alias) };
        if (dialog.ShowDialog() == true) model.SendFiles(peer, dialog.FileNames);
    }

    private static FrameworkElement Empty(ShareModel model) => Ui.Column(4,
        Ui.Text(!model.IsEnabled ? L("Longo Share is off.") : model.IsScanning ? L("Looking for devices…") : L("No devices found yet."), 13, FontWeights.Medium),
        Ui.Text(L("Open LocalSend or Longo Share on the other device, on the same Wi-Fi."), 11.5, color: "TextMuted", wrap: true)).Margin(6, 6, 6, 6);

    private static Border Bar(double fraction)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Clamp(fraction, 0, 1), GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - Math.Clamp(fraction, 0, 1), GridUnitType.Star) });
        grid.Children.Add(new Border { CornerRadius = new CornerRadius(3) }.Res(Border.BackgroundProperty, "Accent"));
        return new Border { Child = grid, Height = 5, CornerRadius = new CornerRadius(3) }.Res(Border.BackgroundProperty, "Tint10");
    }
}

/// <summary>The words for messages: a line for the list, a status, links made clickable.</summary>
internal static class Words
{
    public static string Line(ChatItem item)
    {
        var you = item.Sent ? L("You: ") : "";
        if (item.Text is { } text) return you + Pretty.Shorten(text, 40);
        if (item.State == ChatState.Asking) return L("Wants to send you files");
        return item.Files.Count == 1 ? you + item.Files[0].Name : you + L("{0} files", item.Files.Count);
    }

    public static string Status(ChatItem item, string contact)
    {
        var total = Pretty.Size(item.Total);
        return item.State switch
        {
            ChatState.Asking => item.Files.Count == 1 ? L("1 file · {0}", total) : L("{0} files · {1}", item.Files.Count, total),
            ChatState.Waiting => L("Waiting for {0}…", contact),
            ChatState.Pin => L("PIN needed"),
            ChatState.Transferring => $"{(item.Sent ? L("Sending") : L("Receiving"))} · {Pretty.Size(item.Done)} / {total}",
            ChatState.Done when item.Sent => item.Files.Count == 1 ? L("Sent · {0}", total) : L("{0} files sent · {1}", item.Files.Count, total),
            ChatState.Done => L("Saved to {0}", item.Files.FirstOrDefault()?.Path is { } path ? Path.GetFileName(Path.GetDirectoryName(path)) ?? "" : ""),
            ChatState.Declined => item.Sent ? L("{0} declined", contact) : L("Declined"),
            ChatState.Failed => L("Didn't go through"),
            _ => L("Cancelled"),
        };
    }

    public static string Glyph(ChatState state) => state switch
    {
        ChatState.Asking => "\uE896",
        ChatState.Waiting => "\uE823",
        ChatState.Pin => "\uE72E",
        ChatState.Transferring => "\uE8AB",
        ChatState.Done => "\uE73E",
        ChatState.Declined => "\uE711",
        ChatState.Failed => "\uE7BA",
        _ => "\uE738",
    };

    public static string Color(ChatState state) => state switch
    {
        ChatState.Done => "Emerald",
        ChatState.Declined or ChatState.Failed => "Amber",
        ChatState.Asking or ChatState.Pin or ChatState.Transferring => "VioletLight",
        _ => "TextFaint",
    };

    /// <summary>Text with its links clickable.</summary>
    public static IEnumerable<Inline> Linked(string text, bool onAccent)
    {
        var at = 0;
        foreach (System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(text, @"https?://[^\s]+"))
        {
            if (match.Index > at) yield return new Run(text[at..match.Index]);
            var url = match.Value.TrimEnd('.', ',', ')', '!', '?');
            var link = new Hyperlink(new Run(url));
            link.SetResourceReference(TextElement.ForegroundProperty, onAccent ? "White" : "VioletLight");
            link.Click += (_, _) => Pretty.Open(url);
            yield return link;
            at = match.Index + url.Length;
        }
        if (at < text.Length) yield return new Run(text[at..]);
    }
}

/// <summary>Pictures shown small in the chat, decoded once at the size they're shown.</summary>
internal static class Thumbnails
{
    private static readonly Dictionary<string, BitmapSource?> Cache = new();
    private static readonly string[] Pictures = { ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".webp", ".heic", ".ico" };

    public static bool IsPicture(string path) => Pictures.Contains(Path.GetExtension(path).ToLowerInvariant());

    public static BitmapSource? Image(string path, int width)
    {
        var key = $"{path}|{width}";
        if (Cache.TryGetValue(key, out var cached)) return cached;
        BitmapSource? image = null;
        try
        {
            if (File.Exists(path))
            {
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.UriSource = new Uri(path);
                bitmap.DecodePixelWidth = width * 2;
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
                bitmap.EndInit();
                bitmap.Freeze();
                image = bitmap;
            }
        }
        catch (Exception)
        {
            // Not a picture Windows can read (no codec): its icon instead.
        }
        Cache[key] = image;
        return image;
    }
}
