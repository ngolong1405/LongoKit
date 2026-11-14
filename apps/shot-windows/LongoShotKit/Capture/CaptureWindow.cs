using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using LongoKit.UI;
using LongoShot.Engine;
using static LongoKit.UI.Localizer;

namespace LongoShot.Capture;

/// <summary>
/// One screen while capturing: the screen as frozen, dimmed around the area. The same window picks the area and then
/// edits it, so letting go changes nothing on screen but the grips and the toolbar coming up. Opaque, made once and
/// kept, and everything that follows the pointer is a plain shape moved in place: it keeps up with the hand.
/// </summary>
internal sealed class CaptureWindow : Window
{
    public enum Mode { Picking, Editing, Dimmed }

    private static readonly Brush Solar = Frozen(new SolidColorBrush(Color.FromRgb(0xFF, 0x6B, 0x35)));
    private static readonly Brush Dim = Frozen(new SolidColorBrush(Color.FromArgb(82, 0, 0, 0)));

    public Engine.Screen Screen { get; private set; }
    private readonly Canvas canvas = new() { ClipToBounds = true };
    private readonly Image picture = new() { Stretch = Stretch.Fill };
    private readonly Rectangle[] dims = Enumerable.Range(0, 4).Select(_ => new Rectangle { Fill = Dim, IsHitTestVisible = false }).ToArray();
    private readonly Rectangle edge = new() { Stroke = Solar, StrokeThickness = 1.5, IsHitTestVisible = false };
    private readonly Rectangle[] grips = Enumerable.Range(0, 8).Select(_ => new Rectangle
    {
        Width = 10, Height = 10, RadiusX = 2.5, RadiusY = 2.5, Fill = Brushes.White, Stroke = Solar, StrokeThickness = 1.5, IsHitTestVisible = false,
    }).ToArray();
    private readonly Border sizePill = new() { CornerRadius = new CornerRadius(9), Padding = new Thickness(7, 2, 7, 2), IsHitTestVisible = false, Background = Frozen(new SolidColorBrush(Color.FromArgb(184, 0, 0, 0))) };
    private readonly TextBlock sizeText = new() { Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.SemiBold };
    private readonly Border hint = new() { CornerRadius = new CornerRadius(14), Padding = new Thickness(14, 6, 14, 6), IsHitTestVisible = false, Background = Frozen(new SolidColorBrush(Color.FromArgb(184, 0, 0, 0))) };
    private readonly TextBlock hintText = new() { Foreground = Brushes.White, FontSize = 12, FontWeight = FontWeights.Medium };
    private readonly MarksLayer marks;
    private Toolbar? toolbar;

    private Mode mode;
    private IReadOnlyList<Rect> windows = Array.Empty<Rect>();
    private Rect? area, hovered;
    private Point? dragStart;
    private (Grip? Grip, Rect Start, Point From)? adjusting;
    private Mark? drawing;

    public DrawingState Drawing { get; } = new();
    public Rect? Area => area;
    public double Scale => Screen.Scale;
    public Rect Bounds => new(0, 0, Screen.Bounds.Width / Screen.Scale, Screen.Bounds.Height / Screen.Scale);

    /// <summary>An area was picked (dragged out, a window clicked, or the whole screen double-clicked).</summary>
    public event Action<CaptureWindow, Rect>? Picked;
    public event Action? Cancelled;
    /// <summary>Esc while editing: back to picking, on the same frozen screens.</summary>
    public event Action? Back;
    /// <summary>Done (true: Ctrl+C, copy whatever the clipboard setting), or ✕ (null).</summary>
    public event Action<CaptureWindow, bool?>? Finished;

    public CaptureWindow(Engine.Screen screen)
    {
        Screen = screen;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        Background = Brushes.Black;
        FontFamily = Theme.UI;
        Cursor = Cursors.Cross;
        RenderOptions.SetBitmapScalingMode(picture, BitmapScalingMode.NearestNeighbor);
        sizeText.FontFamily = Theme.Mono;
        sizePill.Child = sizeText;
        hint.Child = hintText;
        marks = new MarksLayer(this);
        canvas.Children.Add(picture);
        canvas.Children.Add(marks);
        foreach (var dim in dims) canvas.Children.Add(dim);
        canvas.Children.Add(edge);
        foreach (var grip in grips) canvas.Children.Add(grip);
        canvas.Children.Add(sizePill);
        canvas.Children.Add(hint);
        Content = canvas;
        Drawing.Changed += () => marks.InvalidateVisual();
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            Native.SetWindowLong(handle, Native.ExStyle, Native.GetWindowLong(handle, Native.ExStyle) | Native.ToolWindow);
            Native.SetWindowDisplayAffinity(handle, Native.ExcludeFromCapture);
            // Up and gone at once: Windows fades windows in and out, which made the screen brighten slowly after a capture.
            var off = 1;
            Native.DwmSetWindowAttribute(handle, Native.TransitionsForceDisabled, ref off, sizeof(int));
            Place();
        };
        // Moved onto a screen at another scale, WPF resizes it: put back where it belongs, in pixels.
        DpiChanged += (_, _) => Place();
    }

    private static T Frozen<T>(T brush) where T : Freezable
    {
        brush.Freeze();
        return brush;
    }

    private void Place()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero) return;
        Native.SetWindowPos(handle, Native.Topmost, Screen.Bounds.X, Screen.Bounds.Y, Screen.Bounds.Width, Screen.Bounds.Height, Native.ShowWindow);
    }

    /// <summary>Shows the screen as frozen, to pick on. <paramref name="windowFrames"/>: the windows on it, in its points.</summary>
    public void Pick(Frozen frozen, IReadOnlyList<Rect> windowFrames, string prompt)
    {
        Screen = frozen.Screen;
        picture.Source = frozen.Picture;
        windows = windowFrames;
        area = hovered = null;
        drawing = null;
        Drawing.Marks.Clear();
        Drawing.Undone.Clear();
        mode = Mode.Picking;
        hintText.Text = prompt;
        Cursor = Cursors.Cross;
        RemoveToolbar();
        if (!IsVisible) Show();
        Place();
        Layout();
    }

    /// <summary>Another screen has the area: this one stays dim.</summary>
    public void DimAll()
    {
        mode = Mode.Dimmed;
        area = hovered = null;
        RemoveToolbar();
        Layout();
    }

    /// <summary>Edits <paramref name="picked"/>: nothing moves, the grips and the toolbar come up.</summary>
    public void Edit(Rect picked)
    {
        mode = Mode.Editing;
        area = picked;
        hovered = null;
        Drawing.Tool = null;
        Drawing.Notify();
        toolbar = new Toolbar(Drawing, copy => Finished?.Invoke(this, copy), () => Finished?.Invoke(this, null));
        canvas.Children.Add(toolbar);
        Layout();
        Activate();
        Focus();
    }

    private void RemoveToolbar()
    {
        if (toolbar == null) return;
        canvas.Children.Remove(toolbar);
        toolbar = null;
    }

    /// <summary>Hidden, kept for the next capture.</summary>
    public void Put()
    {
        RemoveToolbar();
        picture.Source = null;
        Hide();
    }

    // MARK: - Drawing what follows the pointer

    private void Layout()
    {
        var bounds = Bounds;
        canvas.Width = picture.Width = bounds.Width;
        canvas.Height = picture.Height = bounds.Height;
        var cut = mode == Mode.Dimmed ? null : area ?? hovered;
        if (cut is { } c)
        {
            Set(dims[0], 0, 0, bounds.Width, c.Top);
            Set(dims[1], 0, c.Bottom, bounds.Width, bounds.Height - c.Bottom);
            Set(dims[2], 0, c.Top, c.Left, c.Height);
            Set(dims[3], c.Right, c.Top, bounds.Width - c.Right, c.Height);
            edge.Visibility = Visibility.Visible;
            Set(edge, c.X - 1.5, c.Y - 1.5, c.Width + 3, c.Height + 3);
        }
        else
        {
            Set(dims[0], 0, 0, bounds.Width, bounds.Height);
            for (var i = 1; i < 4; i++) Set(dims[i], 0, 0, 0, 0);
            edge.Visibility = Visibility.Collapsed;
        }
        var editing = mode == Mode.Editing && area != null;
        for (var i = 0; i < grips.Length; i++)
        {
            grips[i].Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
            if (editing)
            {
                var point = AreaMath.PointOf((Grip)i, area!.Value);
                Canvas.SetLeft(grips[i], point.X - 5);
                Canvas.SetTop(grips[i], point.Y - 5);
            }
        }
        // The size while dragging an area out, and while adjusting it.
        var showSize = area is { } a && (mode == Mode.Picking || adjusting != null);
        sizePill.Visibility = showSize ? Visibility.Visible : Visibility.Collapsed;
        if (showSize)
        {
            var size = area!.Value;
            sizeText.Text = $"{Math.Round(size.Width * Scale)} × {Math.Round(size.Height * Scale)}";
            Canvas.SetLeft(sizePill, size.X);
            Canvas.SetTop(sizePill, size.Y >= 30 ? size.Y - 26 : size.Bottom + 6);
        }
        hint.Visibility = mode == Mode.Picking && dragStart == null ? Visibility.Visible : Visibility.Collapsed;
        if (hint.Visibility == Visibility.Visible)
        {
            hint.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            Canvas.SetLeft(hint, (bounds.Width - hint.DesiredSize.Width) / 2);
            Canvas.SetTop(hint, 24);
        }
        if (toolbar != null && area is { } edited)
        {
            toolbar.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var at = AreaMath.ToolbarAt(edited, toolbar.DesiredSize, bounds);
            Canvas.SetLeft(toolbar, at.X);
            Canvas.SetTop(toolbar, at.Y);
        }
        marks.Clip = area is { } clip ? new RectangleGeometry(clip) : Geometry.Empty;
    }

    private static void Set(FrameworkElement element, double x, double y, double width, double height)
    {
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
        element.Width = Math.Max(width, 0);
        element.Height = Math.Max(height, 0);
    }

    // MARK: - The pointer

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var point = e.GetPosition(canvas);
        if (mode == Mode.Picking)
        {
            if (dragStart is { } start) area = new Rect(start, point);
            else hovered = windows.Cast<Rect?>().FirstOrDefault(w => w!.Value.Contains(point));
            Layout();
        }
        else if (mode == Mode.Editing && area is { } current)
        {
            if (drawing != null)
            {
                var pixel = new Point(point.X * Scale, point.Y * Scale);
                if (drawing.Tool is Tool.Pen or Tool.Highlighter) drawing.Points.Add(pixel);
                else if (drawing.Points.Count > 1) drawing.Points[^1] = Shifted(drawing.Points[0], pixel, drawing.Tool);
                else drawing.Points.Add(pixel);
                marks.InvalidateVisual();
            }
            else if (adjusting is { } held)
            {
                var delta = point - held.From;
                area = held.Grip is { } grip ? AreaMath.Resize(grip, held.Start, delta, Bounds) : AreaMath.Move(held.Start, delta, Bounds);
                Layout();
            }
            else
            {
                Cursor = CursorAt(point, current);
            }
        }
        base.OnMouseMove(e);
    }

    /// <summary>Shift makes a box square and an ellipse round.</summary>
    private static Point Shifted(Point start, Point end, Tool tool)
    {
        if (tool is not (Tool.Rectangle or Tool.Ellipse) || !Keyboard.IsKeyDown(Key.LeftShift) && !Keyboard.IsKeyDown(Key.RightShift)) return end;
        var side = Math.Max(Math.Abs(end.X - start.X), Math.Abs(end.Y - start.Y));
        return new Point(start.X + (end.X >= start.X ? side : -side), start.Y + (end.Y >= start.Y ? side : -side));
    }

    private Cursor CursorAt(Point point, Rect current)
    {
        if (AreaMath.GripAt(point, current) is { } grip)
            return grip switch
            {
                Grip.Left or Grip.Right => Cursors.SizeWE,
                Grip.Top or Grip.Bottom => Cursors.SizeNS,
                Grip.TopLeft or Grip.BottomRight => Cursors.SizeNWSE,
                _ => Cursors.SizeNESW,
            };
        if (!current.Contains(point)) return Cursors.Arrow;
        return Drawing.Tool == null ? Cursors.SizeAll : Cursors.Cross;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        var point = e.GetPosition(canvas);
        if (mode == Mode.Picking)
        {
            if (e.ClickCount == 2)
            {
                dragStart = null;
                Picked?.Invoke(this, Bounds);
                return;
            }
            dragStart = point;
            area = null;
            CaptureMouse();
        }
        else if (mode == Mode.Editing && area is { } current)
        {
            if (AreaMath.GripAt(point, current) is { } grip) adjusting = (grip, current, point);
            else if (current.Contains(point) && Drawing.Tool is { } tool)
            {
                drawing = new Mark { Tool = tool, Color = Drawing.Color, Width = DrawingState.Sizes[Drawing.Size] * Scale };
                drawing.Points.Add(new Point(point.X * Scale, point.Y * Scale));
            }
            else if (current.Contains(point)) adjusting = (null, current, point);
            else return;
            CaptureMouse();
        }
        base.OnMouseLeftButtonDown(e);
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        if (mode == Mode.Picking)
        {
            var picked = area is { Width: >= 4, Height: >= 4 } dragged ? dragged : dragStart != null ? hovered : null;
            dragStart = null;
            if (picked is { } chosen) Picked?.Invoke(this, chosen);
            else Layout();
        }
        else if (drawing != null)
        {
            if (drawing.IsVisible)
            {
                Drawing.Marks.Add(drawing);
                Drawing.Undone.Clear();
            }
            drawing = null;
            Drawing.Notify();
        }
        else if (adjusting != null)
        {
            adjusting = null;
            Layout();
        }
        base.OnMouseLeftButtonUp(e);
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        if (mode == Mode.Picking) Cancelled?.Invoke();
        base.OnMouseRightButtonUp(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        var control = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        switch (e.Key)
        {
            case Key.Escape when mode == Mode.Editing: Back?.Invoke(); break;
            case Key.Escape: Cancelled?.Invoke(); break;
            case Key.Enter when mode == Mode.Editing: Finished?.Invoke(this, false); break;
            case Key.C when control && mode == Mode.Editing: Finished?.Invoke(this, true); break;
            case Key.Z when control && shift:
            case Key.Y when control: Drawing.Redo(); break;
            case Key.Z when control: Drawing.Undo(); break;
            case Key.A or Key.P or Key.R or Key.O or Key.H when mode == Mode.Editing && !control:
                var tool = e.Key switch { Key.A => Tool.Arrow, Key.P => Tool.Pen, Key.R => Tool.Rectangle, Key.O => Tool.Ellipse, _ => Tool.Highlighter };
                Drawing.Tool = Drawing.Tool == tool ? null : tool;
                Drawing.Notify();
                break;
            default: base.OnKeyDown(e); return;
        }
        e.Handled = true;
    }

    /// <summary>The marks, drawn in the picture's pixels and shown inside the area only.</summary>
    private sealed class MarksLayer : FrameworkElement
    {
        private readonly CaptureWindow owner;

        public MarksLayer(CaptureWindow owner)
        {
            this.owner = owner;
            IsHitTestVisible = false;
        }

        protected override void OnRender(DrawingContext context)
        {
            context.PushTransform(new ScaleTransform(1 / owner.Scale, 1 / owner.Scale));
            foreach (var mark in owner.Drawing.Marks) mark.Draw(context);
            owner.drawing?.Draw(context);
            context.Pop();
        }
    }

    public static string PickPrompt(bool text) => text
        ? L("Drag over the text  ·  Esc: cancel")
        : L("Drag an area  ·  Click a window  ·  Double-click: whole screen  ·  Esc: cancel");
}
