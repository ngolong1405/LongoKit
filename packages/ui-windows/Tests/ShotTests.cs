using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LongoShot.Capture;
using LongoShot.Engine;
using Xunit;

namespace LongoKit.Windows.Tests;

/// <summary>Longo Shot's areas, marks and files.</summary>
public class AreaTests
{
    private static readonly Rect Screen = new(0, 0, 1000, 800);

    [Fact]
    public void AGripResizesItsSides()
    {
        var area = new Rect(100, 100, 200, 100);
        Assert.Equal(new Rect(100, 100, 250, 100), AreaMath.Resize(Grip.Right, area, new Vector(50, 30), Screen));
        Assert.Equal(new Rect(80, 90, 220, 110), AreaMath.Resize(Grip.TopLeft, area, new Vector(-20, -10), Screen));
    }

    [Fact]
    public void DraggingPastTheOppositeEdgeFlips() =>
        Assert.Equal(new Rect(300, 100, 50, 100), AreaMath.Resize(Grip.Left, new Rect(100, 100, 200, 100), new Vector(250, 0), Screen));

    [Fact]
    public void AnAreaStaysOnItsScreen()
    {
        Assert.Equal(new Rect(800, 0, 200, 100), AreaMath.Move(new Rect(700, 50, 200, 100), new Vector(300, -200), Screen));
        Assert.Equal(new Rect(100, 100, 8, 8), AreaMath.Resize(Grip.Right, new Rect(100, 100, 50, 50), new Vector(-49, 0), Screen) with { Height = 8 });
    }

    [Fact]
    public void TheGripUnderThePointer()
    {
        var area = new Rect(100, 100, 200, 100);
        Assert.Equal(Grip.BottomRight, AreaMath.GripAt(new Point(305, 198), area));
        Assert.Equal(Grip.Top, AreaMath.GripAt(new Point(200, 95), area));
        Assert.Null(AreaMath.GripAt(new Point(200, 150), area));
    }

    [Fact]
    public void TheToolbarGoesUnderTheAreaElseAboveElseInside()
    {
        var toolbar = new Size(600, 44);
        Assert.Equal(new Point(200, 210), AreaMath.ToolbarAt(new Rect(300, 100, 400, 100), toolbar, Screen));
        Assert.Equal(new Point(200, 646), AreaMath.ToolbarAt(new Rect(300, 700, 400, 90), toolbar, Screen));
        Assert.Equal(740, AreaMath.ToolbarAt(Screen, toolbar, Screen).Y);
    }

    [Fact]
    public void AnAreaIsCutInsideThePicture() =>
        Assert.Equal(new Int32Rect(0, 10, 50, 40), Screens.Clip(new Int32Rect(-20, 10, 70, 100), 400, 50));

    [Fact]
    public void FilesAreNamedByTheirTime() =>
        Assert.Equal("Longo Shot 2026-11-13 at 22.10.05.png", Output.FileName(new DateTime(2026, 11, 13, 22, 10, 5)));
}

public class MarkTests
{
    private static void OnSta(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { action(); } catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure != null) throw failure;
    }

    [Fact]
    public void AClickWithoutADragDrawsNothing()
    {
        var mark = new Mark { Tool = Tool.Rectangle, Width = 5 };
        mark.Points.Add(new Point(10, 10));
        mark.Points.Add(new Point(12, 11));
        Assert.False(mark.IsVisible);
        mark.Points[^1] = new Point(60, 40);
        Assert.True(mark.IsVisible);
    }

    [Fact]
    public void MarksAreDrawnWhereTheyWereOnTheScreen() => OnSta(() =>
    {
        var white = BitmapSource.Create(200, 100, 96, 96, PixelFormats.Bgra32, null, Enumerable.Repeat((byte)255, 200 * 100 * 4).ToArray(), 200 * 4);
        var box = new Mark { Tool = Tool.Rectangle, Color = Colors.Red, Width = 6 };
        box.Points.Add(new Point(120, 30));
        box.Points.Add(new Point(180, 70));
        // The picture is a part starting at (100, 0) of the screen the marks were drawn on.
        var drawn = Mark.Render(white, new[] { box }, new Point(100, 0));
        var pixels = new byte[4];
        drawn.CopyPixels(new Int32Rect(20, 50, 1, 1), pixels, 4, 0);
        Assert.True(pixels[2] > 200 && pixels[1] < 80, "the box's left edge is red");
        drawn.CopyPixels(new Int32Rect(50, 50, 1, 1), pixels, 4, 0);
        Assert.True(pixels[1] > 200, "inside the box is left white");
    });
}
