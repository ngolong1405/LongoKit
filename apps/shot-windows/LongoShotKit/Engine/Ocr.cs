using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using WinBitmapDecoder = Windows.Graphics.Imaging.BitmapDecoder;

namespace LongoShot.Engine;

/// <summary>
/// Text in a picture, read on the PC by Windows' own recognizer: nothing is uploaded. It reads the languages Windows has
/// (Settings › Time &amp; language › Language: each one's "Optical character recognition").
/// </summary>
public static class Ocr
{
    /// <summary>The languages Windows can read, as (tag, name): "vi", "Tiếng Việt".</summary>
    public static IReadOnlyList<(string Tag, string Name)> Languages()
    {
        try
        {
            return OcrEngine.AvailableRecognizerLanguages.Select(l => (l.LanguageTag, l.NativeName)).OrderBy(l => l.NativeName).ToList();
        }
        catch (Exception)
        {
            return Array.Empty<(string, string)>();
        }
    }

    /// <summary>The lines of text in <paramref name="picture"/>, in <paramref name="language"/> ("auto": the languages of the
    /// person's profile).</summary>
    public static async Task<IReadOnlyList<string>> Read(BitmapSource picture, string language)
    {
        var engine = language == "auto"
            ? OcrEngine.TryCreateFromUserProfileLanguages()
            : OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language(language));
        if (engine == null) return Array.Empty<string>();
        // Small text reads better larger: a capture under 1000 pixels wide is read at twice its size.
        var source = picture.PixelWidth < 1000 ? Scaled(picture, 2) : picture;
        var png = Output.Png(source);
        using var stream = new InMemoryRandomAccessStream();
        await stream.WriteAsync(png.AsBuffer());
        stream.Seek(0);
        var decoder = await WinBitmapDecoder.CreateAsync(stream);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        var result = await engine.RecognizeAsync(bitmap);
        return result.Lines.Select(line => line.Text).Where(text => text.Length > 0).ToList();
    }

    private static BitmapSource Scaled(BitmapSource picture, double factor)
    {
        var scaled = new TransformedBitmap(picture, new ScaleTransform(factor, factor));
        scaled.Freeze();
        return scaled;
    }
}
