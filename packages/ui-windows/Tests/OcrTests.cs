using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LongoShot.Engine;
using Xunit;
using Xunit.Abstractions;

namespace LongoKit.Windows.Tests;

/// <summary>Reading text: Vietnamese keeps its marks (Windows' own recognizer has no Vietnamese).</summary>
public class OcrTests
{
    private readonly ITestOutputHelper output;

    public OcrTests(ITestOutputHelper output) => this.output = output;

    /// <summary>Lines of text drawn as a screen would show them, as PNG.</summary>
    private static byte[] Picture(string[] lines, string font, double size)
    {
        byte[]? png = null;
        var thread = new Thread(() =>
        {
            var visual = new DrawingVisual();
            using (var context = visual.RenderOpen())
            {
                context.DrawRectangle(Brushes.White, null, new Rect(0, 0, 1400, 60 + lines.Length * size * 1.6));
                for (var i = 0; i < lines.Length; i++)
                {
                    var text = new FormattedText(lines[i], CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface(font), size, Brushes.Black, 1);
                    context.DrawText(text, new Point(30, 30 + i * size * 1.6));
                }
            }
            var bitmap = new RenderTargetBitmap(1400, (int)(60 + lines.Length * size * 1.6), 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            png = Output.Png(bitmap);
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        return png!;
    }

    [Fact]
    public async Task VietnameseKeepsItsMarks()
    {
        var lines = new[]
        {
            "Mở ngay trong file cài đặt, app tự đề nghị",
            "chuyển vào Applications rồi xoá file cài đặt.",
            "Chưa notarize. Nếu macOS chặn: Cài đặt hệ thống",
            "Hoặc tự build (cần Command Line Tools của Xcode)",
        };
        foreach (var font in new[] { "Segoe UI", "Consolas" })
        {
            var read = await Ocr.ReadLatin(Picture(lines, font, 26));
            Assert.NotNull(read);
            output.WriteLine($"{font}:\n  " + string.Join("\n  ", read!));
            var all = string.Join(" ", read!);
            foreach (var words in new[] { "cài đặt", "tự đề nghị", "chuyển vào", "rồi xoá", "Nếu", "chặn", "hệ thống", "Hoặc tự build", "cần" })
                Assert.Contains(words, all);
        }
    }

    [Fact]
    public void OtherScriptsAreToldFromLatin()
    {
        Assert.Equal(0, Ocr.OtherScriptShare(new[] { "Phở ở Hàng Bè rất ngon" }));
        Assert.True(Ocr.OtherScriptShare(new[] { "你好世界 hello" }) > 0.3);
    }
}
