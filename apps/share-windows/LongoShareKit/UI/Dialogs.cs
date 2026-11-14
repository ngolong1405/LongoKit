using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using LongoKit.UI;

namespace LongoShare.Windows.UI;

/// <summary>Longo Share's text box, in LongoKit's colors.</summary>
internal static class Dialogs
{
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
    public static Border Badge(DeviceInfo info, double size)
    {
        var glyph = Ui.Glyph(DeviceGlyph(info), size * 0.44, "VioletLight");
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        return new Border { Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), Child = glyph }.Res(Border.BackgroundProperty, "Tint10");
    }

    /// <summary>A file's glyph, by its extension.</summary>
    public static string FileGlyph(string name) => Path.GetExtension(name).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" or ".png" or ".gif" or ".bmp" or ".heic" or ".webp" or ".tif" or ".tiff" => "\uEB9F",
        ".mp4" or ".mov" or ".mkv" or ".avi" or ".webm" => "\uE714",
        ".mp3" or ".m4a" or ".wav" or ".aac" or ".flac" => "\uE8D6",
        ".txt" or ".md" or ".pdf" or ".doc" or ".docx" => "\uE8A5",
        ".zip" or ".rar" or ".7z" => "\uF012",
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
}
