using System.Windows;
using System.Windows.Media.Imaging;

namespace LongoShot.Engine;

/// <summary>Where captures go: the clipboard at once, a PNG file in the save folder written in the background.</summary>
public static class Output
{
    /// <summary>"Longo Shot 2026-11-13 at 22.10.05.png", in the save folder.</summary>
    public static string FileName(DateTime time) => $"Longo Shot {time:yyyy-MM-dd} at {time:HH.mm.ss}.png";

    public static byte[] Png(BitmapSource picture)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(picture));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    /// <summary>Puts the picture on the clipboard, as an image and as PNG (for apps that keep transparency).</summary>
    public static void Copy(BitmapSource picture, byte[]? png = null)
    {
        var data = new DataObject();
        data.SetImage(picture);
        data.SetData("PNG", new MemoryStream(png ?? Png(picture)), false);
        try
        {
            Clipboard.SetDataObject(data, true);
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            // Another app holds the clipboard for a moment: once more.
            Thread.Sleep(50);
            Clipboard.SetDataObject(data, true);
        }
    }

    public static void Copy(string text)
    {
        try { Clipboard.SetText(text); }
        catch (System.Runtime.InteropServices.COMException) { Thread.Sleep(50); Clipboard.SetText(text); }
    }

    /// <summary>Writes the PNG off the UI thread; returns the file's path.</summary>
    public static async Task<string> Save(byte[] png, string folder, DateTime time)
    {
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, FileName(time));
        await File.WriteAllBytesAsync(path, png);
        return path;
    }
}
