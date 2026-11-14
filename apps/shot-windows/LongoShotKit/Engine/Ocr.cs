using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using Tess = Tesseract;
using WinBitmapDecoder = Windows.Graphics.Imaging.BitmapDecoder;

namespace LongoShot.Engine;

/// <summary>
/// Text in a picture, read on the PC: nothing is uploaded. Windows' own recognizer has no Vietnamese, so Latin text
/// (Vietnamese with its marks, English) is read by Tesseract, which comes with the app; Windows reads the languages it
/// has, like Chinese, Japanese or Korean. Automatic reads with both and keeps Windows' only when it found such text.
/// </summary>
public static class Ocr
{
    /// <summary>Vietnamese and English, by Tesseract.</summary>
    public const string Latin = "vie+eng";

    private static readonly object gate = new();
    private static Tess.TesseractEngine? tesseract;
    private static bool tesseractFailed;

    /// <summary>The languages to pick from, as (tag, name): Automatic first, then Tesseract's, then Windows'.</summary>
    public static IReadOnlyList<(string Tag, string Name)> Languages()
    {
        var list = new List<(string, string)>();
        if (TesseractAvailable) list.Add((Latin, "Tiếng Việt & English"));
        try
        {
            list.AddRange(OcrEngine.AvailableRecognizerLanguages.Select(l => (l.LanguageTag, l.NativeName)).OrderBy(l => l.NativeName));
        }
        catch (Exception)
        {
            // No Windows recognizer: Tesseract's languages only.
        }
        return list;
    }

    /// <summary>Whether Tesseract runs here (x64; it needs Microsoft's C++ runtime, which most PCs have).</summary>
    public static bool TesseractAvailable => Engine() != null;

    private static Tess.TesseractEngine? Engine()
    {
        lock (gate)
        {
            if (tesseract != null || tesseractFailed) return tesseract;
            try
            {
                tesseract = new Tess.TesseractEngine(Path.Combine(AppContext.BaseDirectory, "tessdata"), Latin, Tess.EngineMode.LstmOnly);
            }
            catch (Exception)
            {
                tesseractFailed = true;
            }
            return tesseract;
        }
    }

    /// <summary>The lines of text in <paramref name="picture"/>, read as <paramref name="language"/>: "auto", <see cref="Latin"/>,
    /// or a language tag Windows reads ("ja").</summary>
    public static async Task<IReadOnlyList<string>> Read(BitmapSource picture, string language)
    {
        // Small text reads better larger: a capture under 1000 pixels wide is read at twice its size.
        var source = picture.PixelWidth < 1000 ? Scaled(picture, 2) : picture;
        var png = Output.Png(source);
        if (language == Latin) return await ReadLatin(png) ?? await ReadWindows(png, "auto");
        if (language != "auto") return await ReadWindows(png, language);
        var latin = ReadLatin(png);
        // Windows' reading is worth it only for a script Tesseract doesn't have here.
        var others = HasOtherScripts() ? await ReadWindows(png, "auto") : Array.Empty<string>();
        var latinLines = await latin;
        if (latinLines == null) return others.Count > 0 ? others : await ReadWindows(png, "auto");
        return OtherScriptShare(others) > 0.3 ? others : latinLines;
    }

    /// <summary>Tesseract's reading, or null where it can't run.</summary>
    internal static Task<IReadOnlyList<string>?> ReadLatin(byte[] png) => Task.Run<IReadOnlyList<string>?>(() =>
    {
        var engine = Engine();
        if (engine == null) return null;
        lock (gate)
        {
            using var image = Tess.Pix.LoadFromMemory(png);
            using var page = engine.Process(image, Tess.PageSegMode.Auto);
            return page.GetText().Split('\n').Select(line => line.Trim()).Where(line => line.Length > 0).ToList();
        }
    });

    private static async Task<IReadOnlyList<string>> ReadWindows(byte[] png, string language)
    {
        try
        {
            var engine = language == "auto"
                ? OcrEngine.TryCreateFromUserProfileLanguages()
                : OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language(language));
            if (engine == null) return Array.Empty<string>();
            using var stream = new InMemoryRandomAccessStream();
            await stream.WriteAsync(png.AsBuffer());
            stream.Seek(0);
            var decoder = await WinBitmapDecoder.CreateAsync(stream);
            using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            var result = await engine.RecognizeAsync(bitmap);
            return result.Lines.Select(line => line.Text).Where(text => text.Length > 0).ToList();
        }
        catch (Exception)
        {
            return Array.Empty<string>();
        }
    }

    /// <summary>Whether Windows reads a script here that Tesseract doesn't (Chinese, Japanese, Korean, Arabic...).</summary>
    private static bool HasOtherScripts()
    {
        try
        {
            return OcrEngine.AvailableRecognizerLanguages.Any(l => l.LanguageTag.Split('-')[0] is "zh" or "ja" or "ko" or "ar" or "ru" or "el" or "sr" or "uk" or "bg");
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>The share of letters outside the Latin script in <paramref name="lines"/>.</summary>
    internal static double OtherScriptShare(IEnumerable<string> lines)
    {
        int letters = 0, others = 0;
        foreach (var c in lines.SelectMany(l => l))
        {
            if (!char.IsLetter(c)) continue;
            letters++;
            if (c > 0x024F && !(c >= 0x1E00 && c <= 0x1EFF)) others++;
        }
        return letters == 0 ? 0 : (double)others / letters;
    }

    private static BitmapSource Scaled(BitmapSource picture, double factor)
    {
        var scaled = new TransformedBitmap(picture, new ScaleTransform(factor, factor));
        scaled.Freeze();
        return scaled;
    }
}
