using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Forms = System.Windows.Forms;

namespace LongoKit.UI;

/// <summary>
/// The menu from the notification area icon: a module's quick controls under a header with its name, state and
/// power button (LongoKit: each module's, picked from icons along the top). Gone once something else is clicked.
/// </summary>
internal sealed class MenuWindow : Window
{
    private readonly LongoShell shell;
    private ILongoModule current;

    public MenuWindow(LongoShell shell)
    {
        this.shell = shell;
        current = shell.Modules[0];
        Width = 380 + 24;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Deactivated += (_, _) => Hide();
        shell.Changed += () =>
        {
            // The language or appearance changed: built again. A module's own changes update its parts in place.
            if (IsVisible) Refresh();
        };
        Refresh();
    }

    private void Refresh() => Content = new Border { Child = Build(shell, current, Pick), Padding = new Thickness(12) };

    private void Pick(ILongoModule module)
    {
        current = module;
        Refresh();
    }

    /// <summary>Opens at the corner of the screen nearest the notification area (where the pointer is).</summary>
    public void ShowNearTray()
    {
        Opacity = 0;
        Show();
        var pointer = Forms.Cursor.Position;
        var area = Forms.Screen.FromPoint(pointer).WorkingArea;
        var bounds = Forms.Screen.FromPoint(pointer).Bounds;
        var toDips = PresentationSource.FromVisual(this)?.CompositionTarget.TransformFromDevice ?? Matrix.Identity;
        var topLeft = toDips.Transform(new Point(area.Left, area.Top));
        var bottomRight = toDips.Transform(new Point(area.Right, area.Bottom));
        UpdateLayout();
        // The taskbar's side: the menu sits in the corner by it, as Windows' own flyouts do.
        var right = pointer.X > bounds.Left + bounds.Width / 2;
        var bottom = pointer.Y > bounds.Top + bounds.Height / 2;
        Left = right ? bottomRight.X - ActualWidth : topLeft.X;
        Top = bottom ? bottomRight.Y - ActualHeight : topLeft.Y;
        Opacity = 1;
        Activate();
    }

    /// <summary>The menu's content (also drawn on its own for snapshots).</summary>
    public static Border Build(LongoShell shell, ILongoModule module, Action<ILongoModule>? pick = null)
    {
        var body = Ui.Column(12);
        if (shell.IsSuite)
        {
            // LongoKit: a tab per module, the one shown raised.
            var tabs = Ui.Row(4);
            foreach (var each in shell.Modules)
            {
                var image = new Image { Source = Icons.App(each.IconName, 32), Width = 22, Height = 22 };
                var tab = new Button { Content = image, Width = 34, Height = 34, Opacity = each.IsOn ? 1 : 0.45 }.Tip(each.Title);
                tab.SetResourceReference(StyleProperty, "LongoIconButton");
                tab.Click += (_, _) => pick?.Invoke(each);
                var box = new Border { Child = tab, CornerRadius = new CornerRadius(9) };
                if (each == module) box.Res(Border.BackgroundProperty, "Hover");
                tabs.Children.Add(box);
            }
            body.Children.Add(tabs);
        }
        body.Children.Add(Header(module));
        body.Children.Add(Ui.Hairline());
        body.Children.Add(module.CreateMenu());
        body.Children.Add(Ui.Hairline());
        var settings = Ui.Ghost(Localizer.L("Settings…"), () => shell.ShowWindow(module), "\uE713");
        settings.HorizontalAlignment = HorizontalAlignment.Left;
        body.Children.Add(Ui.Spread(settings, Ui.Ghost(Localizer.L("Quit"), shell.Quit, "\uE7E8")));
        var card = new Border
        {
            Width = 380,
            Child = body,
            Padding = new Thickness(16),
            CornerRadius = new CornerRadius(14),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Direction = 270, Opacity = 0.4 },
        };
        return card.Res(Border.BackgroundProperty, "PopoverTop").Res(Border.BorderBrushProperty, "BorderProminent");
    }

    /// <summary>The module's logo, name and state, and its power button.</summary>
    private static FrameworkElement Header(ILongoModule module)
    {
        return new LiveView(() =>
        {
            var logo = new Image { Source = Icons.App(module.IconName, 64), Width = 36, Height = 36 };
            var title = Ui.Column(2, Ui.Text(module.Title, 15, FontWeights.SemiBold, font: "DisplayFont"), PowerLabel(module.IsOn, module.Status));
            var power = new Button
            {
                // Lit (the gradient) while on, as the Mac apps' power button.
                Content = Ui.Glyph("\uE7E8", 12, module.IsOn ? "White" : "TextMuted"),
                Width = 30, Height = 30, Padding = new Thickness(0),
            }.Tip(module.IsOn ? Localizer.L("Turn {0} off", module.Title) : Localizer.L("Turn {0} on", module.Title));
            power.SetResourceReference(StyleProperty, module.IsOn ? "LongoPrimary" : "LongoGhost");
            power.Click += (_, _) => module.SetOn(!module.IsOn);
            return Ui.Spread(Ui.Row(10, logo, title), power);
        }, refresh => module.Changed += refresh, refresh => module.Changed -= refresh);
    }

    /// <summary>The light and word under a module's name: On (and what it's doing), or Off.</summary>
    public static FrameworkElement PowerLabel(bool isOn, string? status = null)
    {
        var color = isOn ? "Emerald" : "TextFaint";
        var dot = new System.Windows.Shapes.Ellipse { Width = 6, Height = 6 }.Res(System.Windows.Shapes.Shape.FillProperty, color);
        var text = isOn ? (string.IsNullOrEmpty(status) ? Localizer.L("On") : status!) : Localizer.L("Off");
        return Ui.Row(6, dot, Ui.Text(text, 11.5, color: isOn ? "Emerald" : "TextMuted"));
    }
}
