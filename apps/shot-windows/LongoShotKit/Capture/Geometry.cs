using System.Windows;

namespace LongoShot.Capture;

/// <summary>An area's eight grips.</summary>
public enum Grip { TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left }

/// <summary>Moving and resizing an area, as the Mac app does (InPlaceEditor.swift).</summary>
public static class AreaMath
{
    public static Point PointOf(Grip grip, Rect area) => grip switch
    {
        Grip.TopLeft => area.TopLeft,
        Grip.Top => new Point(area.X + area.Width / 2, area.Top),
        Grip.TopRight => area.TopRight,
        Grip.Right => new Point(area.Right, area.Y + area.Height / 2),
        Grip.BottomRight => area.BottomRight,
        Grip.Bottom => new Point(area.X + area.Width / 2, area.Bottom),
        Grip.BottomLeft => area.BottomLeft,
        _ => new Point(area.Left, area.Y + area.Height / 2),
    };

    /// <summary><paramref name="area"/> with <paramref name="grip"/> dragged by <paramref name="delta"/>, inside
    /// <paramref name="bounds"/>, at least 8 each way. Dragging past the opposite edge flips it.</summary>
    public static Rect Resize(Grip grip, Rect area, Vector delta, Rect bounds)
    {
        double left = area.Left, top = area.Top, right = area.Right, bottom = area.Bottom;
        if (grip is Grip.TopLeft or Grip.Left or Grip.BottomLeft) left += delta.X;
        if (grip is Grip.TopRight or Grip.Right or Grip.BottomRight) right += delta.X;
        if (grip is Grip.TopLeft or Grip.Top or Grip.TopRight) top += delta.Y;
        if (grip is Grip.BottomLeft or Grip.Bottom or Grip.BottomRight) bottom += delta.Y;
        var next = new Rect(new Point(left, top), new Point(right, bottom));
        next.Intersect(bounds);
        if (next.IsEmpty) next = new Rect(area.Location, new Size(8, 8));
        return new Rect(next.X, next.Y, Math.Max(next.Width, 8), Math.Max(next.Height, 8));
    }

    /// <summary><paramref name="area"/> moved by <paramref name="delta"/>, kept inside <paramref name="bounds"/>.</summary>
    public static Rect Move(Rect area, Vector delta, Rect bounds) => new(
        Math.Clamp(area.X + delta.X, bounds.Left, Math.Max(bounds.Right - area.Width, bounds.Left)),
        Math.Clamp(area.Y + delta.Y, bounds.Top, Math.Max(bounds.Bottom - area.Height, bounds.Top)),
        area.Width, area.Height);

    /// <summary>The grip under <paramref name="point"/>, within a reach of <paramref name="reach"/>.</summary>
    public static Grip? GripAt(Point point, Rect area, double reach = 11) =>
        Enum.GetValues<Grip>().Cast<Grip?>().FirstOrDefault(g => (PointOf(g!.Value, area) - point).Length <= reach);

    /// <summary>Where the toolbar goes: under the area, else above it, else inside at its bottom (the whole screen).</summary>
    public static Point ToolbarAt(Rect area, Size toolbar, Rect bounds)
    {
        const double gap = 10;
        var y = area.Bottom + gap;
        if (y + toolbar.Height > bounds.Bottom)
        {
            y = area.Top - gap - toolbar.Height;
            if (y < bounds.Top) y = Math.Min(area.Bottom, bounds.Bottom) - toolbar.Height - 16;
        }
        var x = Math.Clamp(area.X + area.Width / 2 - toolbar.Width / 2, bounds.Left + 8, Math.Max(bounds.Right - toolbar.Width - 8, bounds.Left + 8));
        return new Point(x, y);
    }
}
