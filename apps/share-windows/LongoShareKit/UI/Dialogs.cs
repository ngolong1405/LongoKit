using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoShare.Windows.UI;

/// <summary>Longo Share's small windows: files coming in, a message, a PIN or some text to type.</summary>
internal static class Dialogs
{
    // MARK: - Files coming in

    /// <summary>Asks whether to take the files; "Always accept" also trusts the device.</summary>
    public static Task<bool> Incoming(IncomingTransfer transfer, Action trust)
    {
        var done = new TaskCompletionSource<bool>();
        var window = Popup(L("Files from {0}", transfer.From.Info.Alias));
        window.Content = Framed(IncomingView(transfer, (accept, always) =>
        {
            if (accept && always) trust();
            done.TrySetResult(accept);
            window.Close();
        }));
        window.Closed += (_, _) => done.TrySetResult(false);
        window.Show();
        window.Activate();
        return done.Task;
    }

    public static FrameworkElement IncomingView(IncomingTransfer transfer, Action<bool, bool> answer)
    {
        var files = transfer.Files;
        var total = files.Sum(f => f.Size);
        var summary = files.Count == 1 ? L("wants to send you a file · {0}", Pretty.Size(total)) : L("wants to send you {0} files · {1}", files.Count, Pretty.Size(total));
        var header = Ui.Row(12, Pretty.Badge(transfer.From.Info, 40),
                            Ui.Column(2, Ui.Text(transfer.From.Info.Alias, 15, FontWeights.SemiBold, font: "DisplayFont"),
                                         Ui.Text(summary, 11.5, color: "TextMuted")));
        var list = Ui.Column(8);
        foreach (var file in files.Take(5))
            list.Children.Add(Ui.Spread(Ui.Row(8, Ui.Glyph(Pretty.FileGlyph(file.FileType), 13, "VioletLight"), Ui.Text(file.FileName, 12.5)),
                                        Ui.Text(Pretty.Size(file.Size), 11, color: "TextMuted", font: "MonoFont")));
        if (files.Count > 5) list.Children.Add(Ui.Text(L("and {0} more", files.Count - 5), 11.5, color: "TextMuted"));
        var always = false;
        var trust = Ui.Setting(L("Always accept from this device"), L("Its files come in without asking from now on."),
                               Ui.Switch(false, on => always = on), "\uE8FB");
        var decline = Ui.Ghost(L("Decline"), () => answer(false, false));
        var accept = Ui.Primary(L("Accept"), () => answer(true, always), "\uE896");
        accept.IsDefault = true;
        decline.IsCancel = true;
        var buttons = Ui.Row(8, decline, accept);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        return Ui.Column(16, header, Ui.Well(list), trust, buttons);
    }

    // MARK: - A message

    public static void Message(Peer from, string text)
    {
        var window = Popup(L("Message from {0}", from.Info.Alias));
        window.Content = Framed(MessageView(from, text, window.Close));
        window.Show();
        window.Activate();
    }

    public static FrameworkElement MessageView(Peer from, string text, Action close)
    {
        var header = Ui.Row(12, Pretty.Badge(from.Info, 40),
                            Ui.Column(2, Ui.Text(from.Info.Alias, 15, FontWeights.SemiBold, font: "DisplayFont"),
                                         Ui.Text(L("sent you a message"), 11.5, color: "TextMuted")));
        var body = new TextBox
        {
            Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, BorderThickness = new Thickness(0), FontSize = 14,
            MaxHeight = 260, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = System.Windows.Media.Brushes.Transparent,
        }.Res(Control.ForegroundProperty, "Text").Res(TextBox.CaretBrushProperty, "Text").Res(Control.FontFamilyProperty, "UIFont");
        var buttons = Ui.Row(8);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        if (Uri.TryCreate(text.Trim(), UriKind.Absolute, out var link) && (link.Scheme == "http" || link.Scheme == "https"))
            buttons.Children.Add(Ui.Ghost(L("Open Link"), () =>
            {
                Pretty.Open(link.ToString());
                close();
            }, "\uE8A7"));
        var dismiss = Ui.Ghost(L("Close"), close);
        dismiss.IsCancel = true;
        buttons.Children.Add(dismiss);
        var copy = Ui.Primary(L("Copy"), () =>
        {
            Clipboard.SetText(text);
            close();
        }, "\uE8C8");
        copy.IsDefault = true;
        buttons.Children.Add(copy);
        return Ui.Column(16, header, Ui.Well(body), buttons);
    }

    // MARK: - Typing something

    public static Task<string?> Pin(Peer peer) =>
        Ask(L("PIN for {0}", peer.Info.Alias), L("{0} asks for a PIN. It's shown on that device.", peer.Info.Alias), "", L("Send"));

    /// <summary>Some text to send: what's on the clipboard to start with.</summary>
    public static Task<string?> Text(Peer peer) =>
        Ask(L("Send Text to {0}", peer.Info.Alias), null, Clipboard.ContainsText() ? Clipboard.GetText() : "", L("Send"), multiline: true);

    public static Task<string?> Address() =>
        Ask(L("Add a Device"), L("Its IP address, as LocalSend shows it (192.168.1.20). Both devices must be on the same network."), "", L("Add"));

    /// <summary>A window with a box to type in; null when it's closed.</summary>
    public static Task<string?> Ask(string title, string? message, string initial, string action, bool multiline = false)
    {
        var done = new TaskCompletionSource<string?>();
        var window = Popup(title);
        var box = Field(initial, multiline);
        var cancel = Ui.Ghost(L("Cancel"), window.Close);
        cancel.IsCancel = true;
        var ok = Ui.Primary(action, () =>
        {
            done.TrySetResult(box.Text);
            window.Close();
        });
        // Enter types a new line in text; Ctrl+Enter sends.
        ok.IsDefault = !multiline;
        box.PreviewKeyDown += (_, e) =>
        {
            if (!multiline || e.Key != Key.Enter || !Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;
            done.TrySetResult(box.Text);
            window.Close();
            e.Handled = true;
        };
        var buttons = Ui.Row(8, cancel, ok);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        var column = Ui.Column(14, Ui.Text(title, 15, FontWeights.SemiBold, font: "DisplayFont"));
        if (message != null) column.Children.Add(Ui.Text(message, 12, color: "TextMuted", wrap: true));
        column.Children.Add(box);
        column.Children.Add(buttons);
        window.Content = Framed(column);
        window.Closed += (_, _) => done.TrySetResult(null);
        window.Loaded += (_, _) =>
        {
            box.Focus();
            box.SelectAll();
        };
        window.Show();
        window.Activate();
        return done.Task;
    }

    /// <summary>A text box in LongoKit's colors.</summary>
    public static TextBox Field(string text, bool multiline = false)
    {
        var box = new TextBox
        {
            Text = text, FontSize = 13, Padding = new Thickness(8, 6, 8, 6), BorderThickness = new Thickness(1),
            VerticalContentAlignment = VerticalAlignment.Center,
        };
        box.Res(Control.BackgroundProperty, "Well").Res(Control.ForegroundProperty, "Text").Res(Control.BorderBrushProperty, "BorderProminent")
           .Res(TextBox.CaretBrushProperty, "Text").Res(Control.FontFamilyProperty, "UIFont");
        if (multiline)
        {
            box.AcceptsReturn = true;
            box.TextWrapping = TextWrapping.Wrap;
            box.MinHeight = 120;
            box.MaxHeight = 280;
            box.VerticalContentAlignment = VerticalAlignment.Top;
            box.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        }
        return box;
    }

    private static Window Popup(string title)
    {
        var window = new Window
        {
            Title = title, Width = 440, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, Topmost = true,
            WindowStartupLocation = WindowStartupLocation.CenterScreen, Icon = Icons.App("share.ico", 32),
        };
        window.Res(Control.BackgroundProperty, "Canvas");
        window.SourceInitialized += (_, _) => TitleBar.Match(window);
        return window;
    }

    private static Border Framed(UIElement content) => new() { Child = content, Padding = new Thickness(20) };
}
