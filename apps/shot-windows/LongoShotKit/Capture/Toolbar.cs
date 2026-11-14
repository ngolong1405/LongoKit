using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoShot.Capture;

/// <summary>The drawing tools, color, size, and undo/redo; shared by the toolbar and the editor.</summary>
public sealed class DrawingState
{
    public static readonly Color[] Palette =
    {
        Color.FromRgb(0xEF, 0x44, 0x44), Color.FromRgb(0xFF, 0x6B, 0x35), Color.FromRgb(0xFA, 0xCC, 0x15), Color.FromRgb(0x22, 0xC5, 0x5E),
        Color.FromRgb(0x3B, 0x82, 0xF6), Color.FromRgb(0x8B, 0x5C, 0xF6), Colors.White, Colors.Black,
    };
    /// <summary>Line widths in points: thin, medium, thick.</summary>
    public static readonly double[] Sizes = { 2.5, 5, 9 };

    /// <summary>The tool picked; none means dragging moves the area (as on the Mac, right after a capture).</summary>
    public Tool? Tool { get; set; }
    public Color Color { get; set; } = Palette[0];
    public int Size { get; set; } = 1;
    public List<Mark> Marks { get; } = new();
    public List<Mark> Undone { get; } = new();
    public event Action? Changed;

    public void Notify() => Changed?.Invoke();

    public void Undo()
    {
        if (Marks.Count == 0) return;
        Undone.Add(Marks[^1]);
        Marks.RemoveAt(Marks.Count - 1);
        Notify();
    }

    public void Redo()
    {
        if (Undone.Count == 0) return;
        Marks.Add(Undone[^1]);
        Undone.RemoveAt(Undone.Count - 1);
        Notify();
    }
}

/// <summary>The bar under a capture: tools, colors, sizes, undo, redo, ✕ and Done. Every button lights up under the pointer.</summary>
internal sealed class Toolbar : Border
{
    private readonly DrawingState state;
    private readonly Action<bool> finish;
    private readonly Action discard;

    /// <param name="finish">Done (true: and copy).</param>
    public Toolbar(DrawingState state, Action<bool> finish, Action discard)
    {
        this.state = state;
        this.finish = finish;
        this.discard = discard;
        CornerRadius = new CornerRadius(14);
        Padding = new Thickness(8, 6, 8, 6);
        BorderThickness = new Thickness(1);
        Background = new SolidColorBrush(Color.FromArgb(245, 0x11, 0x12, 0x16));
        BorderBrush = new SolidColorBrush(Color.FromArgb(36, 255, 255, 255));
        state.Changed += Build;
        Build();
    }

    private void Build()
    {
        var row = Ui.Row(4);
        var tools = Ui.Row(2);
        foreach (var (tool, title, key) in new[] { (Tool.Arrow, L("Arrow"), "A"), (Tool.Pen, L("Pen"), "P"), (Tool.Rectangle, L("Box"), "R"),
                                                   (Tool.Ellipse, L("Circle"), "O"), (Tool.Highlighter, L("Highlighter"), "H") })
        {
            var picked = state.Tool == tool;
            var button = Square(Icon(tool, picked ? Brushes.White : new SolidColorBrush(Color.FromArgb(160, 255, 255, 255))), $"{title} ({key})", () =>
            {
                // Picking the tool that's on puts it down: dragging moves the area again.
                state.Tool = picked ? null : tool;
                state.Notify();
            }, picked ? SolarFill : null);
            tools.Children.Add(button);
        }
        row.Children.Add(new Border { Child = tools, CornerRadius = new CornerRadius(10), Padding = new Thickness(2), Background = new SolidColorBrush(Color.FromArgb(16, 255, 255, 255)) });
        row.Children.Add(Divider());
        foreach (var color in DrawingState.Palette)
        {
            var picked = state.Color == color;
            var swatch = new Grid { Width = 26, Height = 26 };
            swatch.Children.Add(new Ellipse { Width = 18, Height = 18, Fill = new SolidColorBrush(color), Stroke = new SolidColorBrush(Color.FromArgb(64, 255, 255, 255)) });
            swatch.Children.Add(new Ellipse { Width = 26, Height = 26, Stroke = picked ? Brushes.White : Brushes.Transparent, StrokeThickness = 2 });
            row.Children.Add(Square(swatch, null, () =>
            {
                state.Color = color;
                state.Notify();
            }));
        }
        row.Children.Add(Divider());
        for (var index = 0; index < DrawingState.Sizes.Length; index++)
        {
            var size = index;
            var dot = new Ellipse { Width = 4 + index * 4, Height = 4 + index * 4, Fill = state.Size == index ? Brushes.White : new SolidColorBrush(Color.FromArgb(140, 255, 255, 255)) };
            row.Children.Add(Square(dot, new[] { L("Thin"), L("Medium"), L("Thick") }[index], () =>
            {
                state.Size = size;
                state.Notify();
            }, state.Size == index ? Picked : null));
        }
        row.Children.Add(Divider());
        var undo = Square(Ui.Glyph("\uE7A7", 13, "White"), L("Undo") + " (Ctrl+Z)", state.Undo);
        undo.IsEnabled = state.Marks.Count > 0;
        undo.Opacity = undo.IsEnabled ? 1 : 0.35;
        var redo = Square(Ui.Glyph("\uE7A6", 13, "White"), L("Redo") + " (Ctrl+Shift+Z)", state.Redo);
        redo.IsEnabled = state.Undone.Count > 0;
        redo.Opacity = redo.IsEnabled ? 1 : 0.35;
        row.Children.Add(undo);
        row.Children.Add(redo);
        row.Children.Add(Divider());
        row.Children.Add(Square(Ui.Glyph("\uE711", 12, "White"), L("Throw this capture away"), discard, danger: true));
        var done = Ui.Primary(L("Done"), () => finish(true), "\uE73E").Tip(L("Save and copy (Enter or Ctrl+C); Esc goes back to picking the area"));
        done.Margin = new Thickness(4, 0, 0, 0);
        row.Children.Add(done);
        Child = row;
    }

    private static Border Divider() => new() { Width = 1, Height = 22, Margin = new Thickness(6, 0, 6, 0), Background = new SolidColorBrush(Color.FromArgb(31, 255, 255, 255)) };

    // The toolbar is dark in light and dark appearance alike: its colors are its own, not the app's.
    private static readonly Brush Picked = Frozen(Color.FromRgb(0x2F, 0x32, 0x42));
    private static readonly Brush Lit = Frozen(Color.FromArgb(36, 255, 255, 255));
    private static readonly Brush LitRed = Frozen(Color.FromArgb(90, 0xEF, 0x44, 0x44));
    private static readonly Brush SolarFill = Frozen(Color.FromRgb(0xFF, 0x6B, 0x35));

    private static Brush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    /// <summary>A 32 × 30 button: <paramref name="fill"/> behind it when picked, lit under the pointer (red for ✕).</summary>
    private static Border Square(UIElement content, string? tip, Action click, Brush? fill = null, bool danger = false)
    {
        var rest = fill ?? Brushes.Transparent;
        var face = new Border
        {
            Child = content, Width = 32, Height = 30, CornerRadius = new CornerRadius(7), Background = rest,
            Cursor = System.Windows.Input.Cursors.Hand, SnapsToDevicePixels = true,
        }.Tip(tip);
        if (content is FrameworkElement inner)
        {
            inner.HorizontalAlignment = HorizontalAlignment.Center;
            inner.VerticalAlignment = VerticalAlignment.Center;
        }
        face.MouseEnter += (_, _) => face.Background = fill != null ? rest : danger ? LitRed : Lit;
        face.MouseLeave += (_, _) => face.Background = rest;
        face.MouseLeftButtonUp += (_, e) =>
        {
            if (!face.IsEnabled) return;
            e.Handled = true;
            click();
        };
        return face;
    }

    /// <summary>The tools' icons, drawn: they look the same on every Windows.</summary>
    private static UIElement Icon(Tool tool, Brush brush) => tool switch
    {
        Tool.Arrow => Shape("M3,15 L13,5 M7,5 L13,5 L13,11", brush),
        Tool.Pen => Shape("M2,12 C5,4 8,4 9,9 C10,14 13,14 16,6", brush),
        Tool.Rectangle => new Rectangle { Width = 14, Height = 11, Stroke = brush, StrokeThickness = 1.8 },
        Tool.Ellipse => new Ellipse { Width = 14, Height = 14, Stroke = brush, StrokeThickness = 1.8 },
        _ => Shape("M3,13 L11,5 L14,8 L6,16 Z M3,16 L8,16", brush),
    };

    private static System.Windows.Shapes.Path Shape(string data, Brush brush) => new()
    {
        Data = Geometry.Parse(data),
        Stroke = brush,
        StrokeThickness = 1.8,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round,
        StrokeLineJoin = PenLineJoin.Round,
        Width = 18,
        Height = 18,
    };
}
