using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LongoKit.UI;
using LongoShot.Engine;
using LongoShot.Model;
using static LongoKit.UI.Localizer;

namespace LongoShot.Capture;

/// <summary>
/// The text read from a capture (Alt+Shift+3), as on the Mac: the picture, the language, the text to check or edit,
/// and Copy (Ctrl+Enter). Esc closes it without copying.
/// </summary>
internal sealed class TextWindow : Window
{
    private readonly BitmapSource picture;
    private readonly ShotModel model;
    private readonly TextBox text = new()
    {
        AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, BorderThickness = new Thickness(0), Background = Brushes.Transparent,
        FontSize = 14, Padding = new Thickness(12), VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
    };
    private readonly TextBlock status = Ui.Text("", 11.5, color: "TextMuted");
    private IReadOnlyList<string> lines = Array.Empty<string>();
    private bool reading;

    public TextWindow(BitmapSource picture, ShotModel model)
    {
        this.picture = picture;
        this.model = model;
        Title = L("Picture to Text");
        Width = 900;
        Height = 540;
        MinWidth = 700;
        MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;
        Icon = Icons.App("shot.ico", 32);
        this.Res(BackgroundProperty, "Canvas");
        text.Res(ForegroundProperty, "Text").Res(TextBox.CaretBrushProperty, "Text").Res(FontFamilyProperty, "UIFont");
        Content = Build();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) Close();
            else if (e.Key == Key.Enter && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) CopyAndClose();
            else return;
            e.Handled = true;
        };
        Loaded += async (_, _) => await Read();
    }

    private FrameworkElement Build()
    {
        var language = model.State.TextLanguage;
        var name = language == "auto" ? L("Automatic") : Ocr.Languages().FirstOrDefault(l => l.Tag == language).Name ?? language;
        var picker = Ui.Ghost(name, () => { }, "\uE774");
        picker.Click += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = picker, Placement = PlacementMode.Bottom };
            foreach (var (tag, title) in new[] { ("auto", L("Automatic")) }.Concat(Ocr.Languages()))
            {
                var item = new MenuItem { Header = title, IsCheckable = true, IsChecked = tag == language };
                item.Click += async (_, _) =>
                {
                    model.Change(s => s.TextLanguage = tag);
                    Content = Build();
                    await Read();
                };
                menu.Items.Add(item);
            }
            menu.IsOpen = true;
        };
        var header = Ui.Spread(
            Ui.Row(10, new Border { Width = 26, Height = 26, CornerRadius = new CornerRadius(7), Child = Ui.Glyph("\uE8C1", 13, "White") }.Res(Border.BackgroundProperty, "AccentDiagonal"),
                   Ui.Column(1, Ui.Text(L("Picture to Text"), 13, FontWeights.SemiBold), status)),
            Ui.Row(8, Ui.Text(L("Read as"), 11.5, color: "TextMuted"), picker));
        var image = new Image { Source = picture, Stretch = Stretch.Uniform, MaxWidth = picture.PixelWidth, MaxHeight = picture.PixelHeight };
        var well = new Border { Child = image, Padding = new Thickness(16), CornerRadius = new CornerRadius(14) }.Res(Border.BackgroundProperty, "Well");
        var join = Ui.Row(8, Ui.Text(L("Join lines"), 12, color: "TextSecondary"), Ui.Switch(model.State.JoinLines, on =>
        {
            model.Change(s => s.JoinLines = on);
            text.Text = Compose();
        }));
        var textCard = new Border { CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1) }
            .Res(Border.BackgroundProperty, "Island").Res(Border.BorderBrushProperty, "Hairline");
        var textTop = Ui.Spread(Ui.Text(L("Text"), 12, FontWeights.SemiBold), join).Margin(12, 8, 12, 8);
        var textDock = new DockPanel();
        DockPanel.SetDock(textTop, Dock.Top);
        textDock.Children.Add(textTop);
        textDock.Children.Add(text);
        textCard.Child = textDock;
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(420) });
        Grid.SetColumn(textCard, 2);
        body.Children.Add(well);
        body.Children.Add(textCard);
        var footer = Ui.Spread(Ui.Text(L("Edit the text before copying"), 11.5, color: "TextFaint"),
                               Ui.Row(8, Ui.Ghost(L("Close") + "  Esc", Close), Ui.Primary(L("Copy") + "  Ctrl+Enter", CopyAndClose, "\uE8C8")));
        var root = new DockPanel { Margin = new Thickness(16) };
        DockPanel.SetDock(header, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        header.Margin = new Thickness(0, 0, 0, 14);
        footer.Margin = new Thickness(0, 14, 0, 0);
        root.Children.Add(header);
        root.Children.Add(footer);
        root.Children.Add(body);
        return root;
    }

    private async Task Read()
    {
        reading = true;
        UpdateStatus();
        try
        {
            lines = await Ocr.Read(picture, model.State.TextLanguage);
        }
        catch (Exception)
        {
            lines = Array.Empty<string>();
        }
        reading = false;
        text.Text = Compose();
        UpdateStatus();
        text.Focus();
    }

    private string Compose() => string.Join(model.State.JoinLines ? " " : "\n", lines);

    private void UpdateStatus() => status.Text = reading ? L("Reading…")
        : lines.Count == 0 ? L("No text found")
        : (lines.Count == 1 ? L("1 line") : L("{0} lines", lines.Count)) + " · " + L("{0} characters", text.Text.Length);

    private void CopyAndClose()
    {
        if (text.Text.Length > 0)
        {
            Output.Copy(text.Text);
            Toast.Show(Ui.Text(text.Text.Length > 120 ? text.Text[..120] + "…" : text.Text, 12, color: "TextSecondary", wrap: true), L("Text copied"));
        }
        Close();
    }
}
