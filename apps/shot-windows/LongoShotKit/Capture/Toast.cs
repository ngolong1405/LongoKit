using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoShot.Capture;

/// <summary>After a capture, a small card in the corner: the picture and what happened to it. Click: open it.</summary>
internal static class Toast
{
    private static Window? card;
    private static readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(4) };

    static Toast() => timer.Tick += (_, _) => Hide();

    public static void Show(BitmapSource picture, string? file, bool copied) =>
        Show(new Image { Source = picture, MaxWidth = 220, MaxHeight = 140, Stretch = Stretch.Uniform },
             file != null ? (copied ? L("Saved and copied") : L("Saved")) : L("Copied"), file);

    public static void Show(UIElement preview, string message, string? file = null)
    {
        Hide();
        var body = Ui.Column(8, new Border { Child = preview, CornerRadius = new CornerRadius(6), ClipToBounds = true },
                             Ui.Row(6, Ui.Glyph("\uE73E", 12, "Emerald"), Ui.Text(message, 12.5, FontWeights.Medium)));
        var box = new Border { Child = body, MaxWidth = 280, Padding = new Thickness(12), CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1) }
            .Res(Border.BackgroundProperty, "PopoverTop").Res(Border.BorderBrushProperty, "BorderProminent");
        card = new Window
        {
            Content = new Border { Child = box, Padding = new Thickness(8) },
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            SizeToContent = SizeToContent.WidthAndHeight,
            Cursor = file != null ? System.Windows.Input.Cursors.Hand : null,
        };
        card.MouseLeftButtonUp += (_, _) =>
        {
            if (file != null) Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
            Hide();
        };
        card.MouseEnter += (_, _) => timer.Stop();
        card.MouseLeave += (_, _) => timer.Start();
        card.Loaded += (_, _) =>
        {
            var area = SystemParameters.WorkArea;
            card.Left = area.Right - card.ActualWidth - 8;
            card.Top = area.Bottom - card.ActualHeight - 8;
        };
        card.Show();
        timer.Start();
    }

    public static void Hide()
    {
        timer.Stop();
        card?.Close();
        card = null;
    }
}
