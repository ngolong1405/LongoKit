using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace LongoKit.UI;

/// <summary>A row or column with a gap between its children (WPF's StackPanel has none).</summary>
public sealed class Stack : Panel
{
    public Orientation Orientation { get; set; } = Orientation.Vertical;
    public double Spacing { get; set; }

    protected override Size MeasureOverride(Size available)
    {
        double along = 0, across = 0;
        var visible = 0;
        foreach (UIElement child in InternalChildren)
        {
            child.Measure(Orientation == Orientation.Vertical
                ? new Size(available.Width, double.PositiveInfinity)
                : new Size(double.PositiveInfinity, available.Height));
            if (child.Visibility == Visibility.Collapsed) continue;
            visible++;
            var size = child.DesiredSize;
            along += Orientation == Orientation.Vertical ? size.Height : size.Width;
            across = Math.Max(across, Orientation == Orientation.Vertical ? size.Width : size.Height);
        }
        along += Math.Max(visible - 1, 0) * Spacing;
        return Orientation == Orientation.Vertical ? new Size(across, along) : new Size(along, across);
    }

    protected override Size ArrangeOverride(Size final)
    {
        double offset = 0;
        foreach (UIElement child in InternalChildren)
        {
            if (child.Visibility == Visibility.Collapsed) continue;
            var size = child.DesiredSize;
            if (Orientation == Orientation.Vertical)
            {
                child.Arrange(new Rect(0, offset, final.Width, size.Height));
                offset += size.Height + Spacing;
            }
            else
            {
                child.Arrange(new Rect(offset, 0, size.Width, final.Height));
                offset += size.Width + Spacing;
            }
        }
        return final;
    }
}

/// <summary>
/// A piece of a page built again whenever its source says something changed, but not while the pointer holds a
/// control in it (a slider being dragged): then once it's let go.
/// </summary>
public sealed class LiveView : ContentControl
{
    private readonly Func<FrameworkElement> build;
    private bool pending;

    public LiveView(Func<FrameworkElement> build, Action<Action> subscribe, Action<Action> unsubscribe)
    {
        this.build = build;
        Content = build();
        Focusable = false;
        Loaded += (_, _) => subscribe(Refresh);
        Unloaded += (_, _) => unsubscribe(Refresh);
        PreviewMouseUp += (_, _) =>
        {
            if (pending) Dispatcher.BeginInvoke(Refresh);
        };
    }

    public void Refresh()
    {
        if (Mouse.Captured is DependencyObject held && IsAncestorOf(held))
        {
            pending = true;
            return;
        }
        pending = false;
        Content = build();
    }
}

/// <summary>Building LongoKit's views in code, in the Mac apps' look.</summary>
public static class Ui
{
    public static T Res<T>(this T element, DependencyProperty property, string key) where T : FrameworkElement
    {
        element.SetResourceReference(property, key);
        return element;
    }

    public static T Margin<T>(this T element, double left, double top, double right, double bottom) where T : FrameworkElement
    {
        element.Margin = new Thickness(left, top, right, bottom);
        return element;
    }

    public static T Tip<T>(this T element, string? tip) where T : FrameworkElement
    {
        if (!string.IsNullOrEmpty(tip)) element.ToolTip = tip;
        return element;
    }

    public static TextBlock Text(string text, double size = 13, FontWeight? weight = null, string color = "Text",
                                 string font = "UIFont", bool wrap = false)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight ?? FontWeights.Normal,
            TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap,
            TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        block.Res(TextBlock.ForegroundProperty, color).Res(TextBlock.FontFamilyProperty, font);
        return block;
    }

    /// <summary>A Segoe Fluent Icons glyph.</summary>
    public static TextBlock Glyph(string glyph, double size = 14, string color = "TextMuted") =>
        Text(glyph, size, color: color, font: "IconFont");

    public static Stack Column(double spacing, params UIElement?[] children) => Fill(new Stack { Spacing = spacing }, children);

    public static Stack Row(double spacing, params UIElement?[] children) =>
        Fill(new Stack { Orientation = Orientation.Horizontal, Spacing = spacing }, children);

    private static Stack Fill(Stack stack, UIElement?[] children)
    {
        foreach (var child in children)
            if (child != null) stack.Children.Add(child);
        return stack;
    }

    /// <summary>Content on the left, <paramref name="trailing"/> on the right.</summary>
    public static DockPanel Spread(UIElement leading, UIElement? trailing)
    {
        var dock = new DockPanel { LastChildFill = true };
        if (trailing != null)
        {
            DockPanel.SetDock(trailing, Dock.Right);
            dock.Children.Add(trailing);
        }
        dock.Children.Add(leading);
        return dock;
    }

    /// <summary>A panel: the raised card every page groups its settings in.</summary>
    public static Border Card(UIElement content, double padding = 16, double radius = 14)
    {
        var card = new Border
        {
            Child = content,
            Padding = new Thickness(padding),
            CornerRadius = new CornerRadius(radius),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 2, Direction = 270, Opacity = Theme.IsDark ? 0.35 : 0.08 },
        };
        return card.Res(Border.BackgroundProperty, "Island").Res(Border.BorderBrushProperty, "Hairline");
    }

    /// <summary>A sunken well, for a group inside a card.</summary>
    public static Border Well(UIElement content, double padding = 12) =>
        new Border { Child = content, Padding = new Thickness(padding), CornerRadius = new CornerRadius(10) }
            .Res(Border.BackgroundProperty, "Well");

    public static Border Hairline() => new Border { Height = 1 }.Res(Border.BackgroundProperty, "Hairline");

    /// <summary>A small colored label: "On", "DDC/CI", "Built-in".</summary>
    public static Border Chip(string text, string color = "TextMuted", bool dot = false)
    {
        var label = Row(5, dot ? new System.Windows.Shapes.Ellipse { Width = 6, Height = 6 }.Res(System.Windows.Shapes.Shape.FillProperty, color) : null,
                        Text(text, 10.5, FontWeights.SemiBold, color, "MonoFont"));
        var chip = new Border
        {
            Child = label,
            Padding = new Thickness(7, 2, 7, 2),
            CornerRadius = new CornerRadius(5),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
        };
        return chip.Res(Border.BackgroundProperty, "Tint04").Res(Border.BorderBrushProperty, "Tint10");
    }

    /// <summary>A section's heading, above its card.</summary>
    public static TextBlock Section(string title) => Text(title, 13, FontWeights.SemiBold).Margin(2, 6, 0, 0);

    /// <summary>A setting: its name (and what it does, under it) on the left, its control on the right.</summary>
    public static FrameworkElement Setting(string title, string? help, UIElement? control, string? glyph = null)
    {
        var text = Column(2, Text(title, 13, FontWeights.Medium), help == null ? null : Text(help, 11.5, color: "TextMuted", wrap: true));
        text.VerticalAlignment = VerticalAlignment.Center;
        // A dock, not a row: the text gets the width that's left, so its help wraps.
        var leading = new DockPanel { VerticalAlignment = VerticalAlignment.Center };
        if (glyph != null)
        {
            var icon = Glyph(glyph, 16, "VioletLight").Margin(0, 0, 12, 0);
            DockPanel.SetDock(icon, Dock.Left);
            leading.Children.Add(icon);
        }
        leading.Children.Add(text);
        if (control is FrameworkElement element) element.VerticalAlignment = VerticalAlignment.Center;
        var row = Spread(leading, control);
        if (control is FrameworkElement trailing) trailing.Margin = new Thickness(16, 0, 0, 0);
        return row;
    }

    public static ToggleButton Switch(bool isOn, Action<bool> changed, string? tip = null)
    {
        var toggle = new ToggleButton { IsChecked = isOn }.Tip(tip);
        toggle.SetResourceReference(FrameworkElement.StyleProperty, "LongoSwitch");
        toggle.Click += (_, _) => changed(toggle.IsChecked == true);
        return toggle;
    }

    /// <summary>A level from <paramref name="minimum"/> to <paramref name="maximum"/>, reporting while it's dragged.</summary>
    public static Slider Level(double value, Action<double> changed, double minimum = 0, double maximum = 1, string? tip = null)
    {
        var slider = new Slider { Minimum = minimum, Maximum = maximum, Value = value, SmallChange = 0.01, LargeChange = 0.0625 }.Tip(tip);
        slider.SetResourceReference(FrameworkElement.StyleProperty, "LongoSlider");
        slider.ValueChanged += (_, e) =>
        {
            // Only the person's changes: setting the value from the model doesn't report back.
            if (slider.IsMouseCaptureWithin || slider.IsKeyboardFocusWithin || slider.IsMouseOver) changed(e.NewValue);
        };
        return slider;
    }

    public static Button Primary(string title, Action click, string? glyph = null) => MakeButton("LongoPrimary", title, click, glyph, "White");

    public static Button Ghost(string title, Action click, string? glyph = null) => MakeButton("LongoGhost", title, click, glyph, "Text");

    private static Button MakeButton(string style, string title, Action click, string? glyph, string color)
    {
        var label = glyph == null ? (UIElement)Text(title, 12, FontWeights.Medium, color) : Row(6, Glyph(glyph, 12, color), Text(title, 12, FontWeights.Medium, color));
        var button = new Button { Content = label };
        button.SetResourceReference(FrameworkElement.StyleProperty, style);
        button.Click += (_, _) => click();
        return button;
    }

    public static Button IconButton(string glyph, Action click, string? tip = null)
    {
        var button = new Button { Content = Glyph(glyph, 13, "TextMuted") }.Tip(tip);
        button.SetResourceReference(FrameworkElement.StyleProperty, "LongoIconButton");
        button.Click += (_, _) => click();
        return button;
    }

    /// <summary>A segmented control: one of a few choices, the picked one raised.</summary>
    public static Border Segmented<T>(IEnumerable<(T Value, string Title)> choices, T selected, Action<T> pick) where T : notnull
    {
        var group = Guid.NewGuid().ToString();
        var row = Row(2);
        foreach (var (value, title) in choices)
        {
            var choice = new RadioButton { Content = title, GroupName = group, IsChecked = EqualityComparer<T>.Default.Equals(value, selected) };
            choice.SetResourceReference(FrameworkElement.StyleProperty, "LongoSegment");
            choice.Checked += (_, _) => pick(value);
            row.Children.Add(choice);
        }
        return new Border { Child = row, Padding = new Thickness(3), CornerRadius = new CornerRadius(9), VerticalAlignment = VerticalAlignment.Center }
            .Res(Border.BackgroundProperty, "SegmentTrack");
    }

    /// <summary>Content that scrolls, with LongoKit's slim scroll bar.</summary>
    public static ScrollViewer Scroll(UIElement content) =>
        new() { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };

    /// <summary>A percentage, like "62%".</summary>
    public static string Percent(double value) => $"{Math.Round(value * 100)}%";
}
