using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace LongoShot.Capture;

public enum Tool { Arrow, Pen, Rectangle, Ellipse, Highlighter }

/// <summary>
/// Something drawn on a capture, the same shapes as the Mac app's (Marks.swift). Points are in the picture's pixels
/// from its top-left, so the same marks draw on screen (scaled) and into the saved picture (as they are).
/// </summary>
public sealed class Mark
{
    public Tool Tool { get; init; }
    public List<Point> Points { get; } = new();
    public Color Color { get; init; }
    /// <summary>Line width in pixels.</summary>
    public double Width { get; init; }

    /// <summary>Long enough to keep: a click without a drag draws nothing.</summary>
    public bool IsVisible
    {
        get
        {
            if (Points.Count == 0) return false;
            if (Tool is Tool.Pen or Tool.Highlighter) return Points.Count > 1;
            var (first, last) = (Points[0], Points[^1]);
            return (last - first).Length > Width;
        }
    }

    public void Draw(DrawingContext context)
    {
        if (Points.Count == 0) return;
        var brush = new SolidColorBrush(Color);
        brush.Freeze();
        var (first, last) = (Points[0], Points[^1]);
        var box = new Rect(first, last);
        switch (Tool)
        {
            case Tool.Arrow:
                context.DrawGeometry(brush, null, Arrow(first, last));
                break;
            case Tool.Rectangle:
                context.DrawRectangle(null, Pen(brush, PenLineJoin.Miter), box);
                break;
            case Tool.Ellipse:
                context.DrawEllipse(null, Pen(brush, PenLineJoin.Round), new Point(box.X + box.Width / 2, box.Y + box.Height / 2), box.Width / 2, box.Height / 2);
                break;
            case Tool.Pen:
                context.DrawGeometry(null, Pen(brush, PenLineJoin.Round), Smooth());
                break;
            case Tool.Highlighter:
                var marker = new SolidColorBrush(Color.FromArgb(102, Color.R, Color.G, Color.B));
                marker.Freeze();
                var pen = new Pen(marker, Width * 3.5) { StartLineCap = PenLineCap.Flat, EndLineCap = PenLineCap.Flat, LineJoin = PenLineJoin.Round };
                pen.Freeze();
                context.DrawGeometry(null, pen, Smooth());
                break;
        }
    }

    private Pen Pen(Brush brush, PenLineJoin join)
    {
        var pen = new Pen(brush, Width) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = join };
        pen.Freeze();
        return pen;
    }

    /// <summary>One solid shape: a shaft widening from a fine tail to a sharp head with swept-back barbs.</summary>
    private Geometry Arrow(Point start, Point end)
    {
        var length = (end - start).Length;
        if (length <= 0) return Geometry.Empty;
        var along = (end - start) / length;
        var across = new Vector(-along.Y, along.X);
        Point At(double back, double side) => end - along * back + across * side;
        var head = Math.Min(Math.Max(Width * 6, 24), length * 0.55);
        double barb = head * 0.48, neck = head * 0.7, shaft = Width * 0.75, tail = Width * 0.25;
        var outline = new[] { At(length, tail), At(neck, shaft), At(head, barb), end, At(head, -barb), At(neck, -shaft), At(length, -tail) };
        var figure = new PathFigure(outline[0], outline.Skip(1).Select(p => (PathSegment)new LineSegment(p, true)), true) { IsFilled = true };
        var geometry = new PathGeometry(new[] { figure });
        geometry.Freeze();
        return geometry;
    }

    /// <summary>The points joined with curves through their midpoints, so a hand-drawn line comes out smooth.</summary>
    private Geometry Smooth()
    {
        var figure = new PathFigure { StartPoint = Points[0] };
        for (var i = 1; i < Points.Count; i++)
        {
            var (previous, point) = (Points[i - 1], Points[i]);
            figure.Segments.Add(new QuadraticBezierSegment(previous, new Point((previous.X + point.X) / 2, (previous.Y + point.Y) / 2), true));
        }
        figure.Segments.Add(new LineSegment(Points[^1], true));
        var geometry = new PathGeometry(new[] { figure });
        geometry.Freeze();
        return geometry;
    }

    /// <summary>The picture with the marks drawn on it, at its full size. <paramref name="origin"/>: where it starts in the
    /// marks' pixels, for a part cut from a larger picture (the marks keep their place).</summary>
    public static BitmapSource Render(BitmapSource picture, IReadOnlyList<Mark> marks, Point origin = default)
    {
        if (marks.Count == 0) return picture;
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.DrawImage(picture, new Rect(0, 0, picture.PixelWidth, picture.PixelHeight));
            context.PushTransform(new TranslateTransform(-origin.X, -origin.Y));
            foreach (var mark in marks) mark.Draw(context);
            context.Pop();
        }
        var result = new RenderTargetBitmap(picture.PixelWidth, picture.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        result.Render(visual);
        result.Freeze();
        return result;
    }
}
