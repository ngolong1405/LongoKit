using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace LongoKit.UI;

/// <summary>A module that can fill itself with sample displays, files... so its pages can be drawn without them.</summary>
public interface ISampleData
{
    void UseSampleData();
}

/// <summary>
/// `--snapshot folder`: every page of the window and the menu, dark and light, English and Vietnamese, as PNGs. CI
/// keeps them, so the pages can be looked at without a Windows PC.
/// </summary>
internal static class Snapshot
{
    public static int Render(LongoShell shell, string folder)
    {
        Directory.CreateDirectory(folder);
        try
        {
            return RenderAll(shell, folder);
        }
        catch (Exception error)
        {
            // A WinExe has no console: the error goes next to the pictures, for CI to show.
            File.WriteAllText(Path.Combine(folder, "error.txt"), error.ToString());
            return 1;
        }
    }

    private static int RenderAll(LongoShell shell, string folder)
    {
        foreach (var module in shell.Modules) (module as ISampleData)?.UseSampleData();
        var count = 0;
        foreach (var appearance in new[] { Appearance.Dark, Appearance.Light })
        foreach (var language in new[] { AppLanguage.English, AppLanguage.Vietnamese })
        {
            Theme.Apply(appearance);
            Localizer.Language = language;
            var prefix = $"{appearance.ToString().ToLowerInvariant()}-{(language == AppLanguage.English ? "en" : "vi")}";
            foreach (var module in shell.Modules)
            {
                var name = shell.Modules.Count == 1 ? "" : module.Id + "-";
                for (var tab = 0; tab <= module.Tabs.Count; tab++)
                {
                    Save(Framed(SettingsWindow.Build(shell, module, tab), 760, "Canvas"), Path.Combine(folder, $"{prefix}-{name}{tab + 1}.png"));
                    count++;
                }
                Save(Framed(MenuWindow.Build(shell, module), 404, "Canvas", 12), Path.Combine(folder, $"{prefix}-{name}menu.png"));
                count++;
            }
        }
        File.WriteAllText(Path.Combine(folder, "done.txt"), $"{count} pictures");
        return 0;
    }

    private static Border Framed(FrameworkElement content, double width, string background, double padding = 0) =>
        new Border { Child = content, Width = width, Padding = new Thickness(padding) }.Res(Border.BackgroundProperty, background);

    private static void Save(FrameworkElement element, string path)
    {
        // Resources and fonts are looked up once it's in a tree: a window that's never shown hosts it.
        var host = new Window { Content = element, SizeToContent = SizeToContent.WidthAndHeight, WindowStyle = WindowStyle.None, ShowInTaskbar = false };
        element.Measure(new Size(element.Width, double.PositiveInfinity));
        element.Arrange(new Rect(element.DesiredSize));
        element.UpdateLayout();
        var scale = 2.0;
        var size = element.DesiredSize;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width * scale), (int)Math.Ceiling(Math.Min(size.Height, 4000) * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(element);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(path);
        encoder.Save(file);
        host.Content = null;
        host.Close();
    }
}
