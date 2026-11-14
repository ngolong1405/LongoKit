using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace LongoKit.UI;

/// <summary>
/// The settings window: the module's pages as tabs along the top (General first, About last), as in the Mac apps.
/// LongoKit has its modules down a sidebar. Windows' own title bar, in the app's colors.
/// </summary>
internal sealed class SettingsWindow : Window
{
    private readonly LongoShell shell;
    /// <summary>The module shown; null for LongoKit's own pages (its modules, the app settings).</summary>
    private ILongoModule? module;
    private int tab;

    public SettingsWindow(LongoShell shell)
    {
        this.shell = shell;
        module = !shell.IsSuite ? shell.Modules[0] : null;
        Title = shell.Info.Name;
        Width = shell.IsSuite ? 980 : 760;
        Height = 780;
        MinWidth = 640;
        MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = Icons.App(shell.Info.IconName, 32);
        this.Res(BackgroundProperty, "Canvas");
        SourceInitialized += (_, _) => TitleBar.Match(this);
        // Closing only hides it: the app keeps running in the notification area.
        Closing += (_, e) =>
        {
            e.Cancel = true;
            Hide();
        };
        shell.Changed += () =>
        {
            TitleBar.Match(this);
            if (IsVisible) Refresh();
        };
        foreach (var each in shell.Modules)
        {
            each.OpenTab += index =>
            {
                module = each;
                tab = index;
                Refresh();
            };
        }
        IsVisibleChanged += (_, _) =>
        {
            if (IsVisible) Refresh();
        };
        Refresh();
    }

    public void Open(ILongoModule module, int tab = 0)
    {
        this.module = module;
        this.tab = tab;
        Refresh();
    }

    private void Refresh() => Content = Build(shell, module, tab, (picked, index) =>
    {
        module = picked;
        tab = index;
        Refresh();
    });

    /// <summary>The window's content (also drawn on its own for snapshots).</summary>
    public static FrameworkElement Build(LongoShell shell, ILongoModule? module, int tab, Action<ILongoModule?, int>? go = null)
    {
        var tabs = module?.Tabs.ToList() ?? new List<ModuleTab> { new(Localizer.L("General"), "\uE713", () => Pages.KitGeneral(shell)) };
        tabs.Add(new ModuleTab(Localizer.L("About"), "\uE946", () => Pages.About(shell, module)));
        tab = Math.Clamp(tab, 0, tabs.Count - 1);

        var picker = Ui.Row(4);
        for (var index = 0; index < tabs.Count; index++)
        {
            var each = index;
            var choice = new RadioButton
            {
                GroupName = "tabs",
                IsChecked = index == tab,
                Padding = new Thickness(14, 6, 14, 6),
                Content = Ui.Column(3, Ui.Glyph(tabs[index].Glyph, 16, index == tab ? "Solar" : "TextMuted"),
                                    Ui.Text(tabs[index].Title, 12, FontWeights.Medium, index == tab ? "Solar" : "TextMuted")),
            };
            ((Stack)choice.Content).Children.OfType<TextBlock>().ToList().ForEach(t => t.HorizontalAlignment = HorizontalAlignment.Center);
            choice.SetResourceReference(StyleProperty, "LongoSegment");
            choice.Checked += (_, _) => go?.Invoke(module, each);
            picker.Children.Add(choice);
        }
        picker.HorizontalAlignment = HorizontalAlignment.Center;

        var title = Ui.Row(10, new Image { Source = Icons.App(module?.IconName ?? shell.Info.IconName, 64), Width = 30, Height = 30 },
                           Ui.Text(module?.Title ?? shell.Info.Name, 18, FontWeights.SemiBold, font: "DisplayFont"));
        var state = module == null ? null : new LiveView(() => MenuWindow.PowerLabel(module.IsOn, module.Status),
                                                         refresh => module.Changed += refresh, refresh => module.Changed -= refresh);
        var header = Ui.Column(14, Ui.Spread(title, state), picker);
        var top = new Border { Child = header, Padding = new Thickness(24, 16, 24, 12), BorderThickness = new Thickness(0, 0, 0, 1) }
            .Res(Border.BackgroundProperty, "Chrome").Res(Border.BorderBrushProperty, "Hairline");

        var page = tabs[tab].Create();
        // A module's own app has the app settings under its first page that scrolls (General).
        if (tab == tabs.FindIndex(t => !t.Fill) && !shell.IsSuite) page = Ui.Column(16, page, Ui.Section(Localizer.L("App")), Pages.AppCard(shell));
        FrameworkElement body = tabs[tab].Fill ? page : Ui.Scroll(new Border { Child = page, Padding = new Thickness(24, 20, 24, 24) });

        var content = new DockPanel();
        DockPanel.SetDock(top, Dock.Top);
        content.Children.Add(top);
        content.Children.Add(body);
        if (!shell.IsSuite) return content;

        // LongoKit: its own page, then the modules down a sidebar, each with its state.
        var sidebar = Ui.Column(4);
        var home = new Button
        {
            Content = Ui.Row(10, new Image { Source = Icons.App(shell.Info.IconName, 32), Width = 24, Height = 24 },
                             Ui.Text(shell.Info.Name, 13, FontWeights.SemiBold)),
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(10, 0, 10, 0),
            Height = 44, Width = 196,
        };
        home.SetResourceReference(StyleProperty, "LongoIconButton");
        home.Click += (_, _) => go?.Invoke(null, 0);
        var homeBox = new Border { Child = home, CornerRadius = new CornerRadius(9), Margin = new Thickness(0, 0, 0, 8) };
        if (module == null) homeBox.Res(Border.BackgroundProperty, "Hover");
        sidebar.Children.Add(homeBox);
        sidebar.Children.Add(Ui.Text(Localizer.L("MODULES"), 10.5, FontWeights.SemiBold, "TextFaint", "MonoFont").Margin(10, 0, 0, 4));
        foreach (var each in shell.Modules)
        {
            var row = new Button
            {
                Content = Ui.Row(10, new Image { Source = Icons.App(each.IconName, 32), Width = 24, Height = 24 },
                                 Ui.Column(1, Ui.Text(each.Title, 13, FontWeights.Medium), MenuWindow.PowerLabel(each.IsOn))),
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(10, 0, 10, 0),
                Height = 48, Width = 196,
            };
            row.SetResourceReference(StyleProperty, "LongoIconButton");
            row.Click += (_, _) => go?.Invoke(each, 0);
            row.Opacity = each.IsOn ? 1 : 0.6;
            var box = new Border { Child = row, CornerRadius = new CornerRadius(9) };
            if (each == module) box.Res(Border.BackgroundProperty, "Hover");
            sidebar.Children.Add(box);
        }
        var side = new Border { Child = sidebar, Width = 220, Padding = new Thickness(12), BorderThickness = new Thickness(0, 0, 1, 0) }
            .Res(Border.BackgroundProperty, "Chrome").Res(Border.BorderBrushProperty, "Hairline");
        var split = new DockPanel();
        DockPanel.SetDock(side, Dock.Left);
        split.Children.Add(side);
        split.Children.Add(content);
        return split;
    }
}

/// <summary>Windows 11's title bar in the app's colors: dark or light, the canvas color behind the title.</summary>
public static class TitleBar
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    private const int UseImmersiveDarkMode = 20;
    private const int CaptionColor = 35;
    private const int TextColor = 36;

    public static void Match(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        var dark = Theme.IsDark ? 1 : 0;
        DwmSetWindowAttribute(handle, UseImmersiveDarkMode, ref dark, sizeof(int));
        // Windows 11 only; Windows 10 ignores these and keeps its own colors.
        var caption = ColorRef(Theme.IsDark ? 0x0B0C10u : 0xF5F6F8u);
        DwmSetWindowAttribute(handle, CaptionColor, ref caption, sizeof(int));
        var text = ColorRef(Theme.IsDark ? 0xF3F4F6u : 0x111827u);
        DwmSetWindowAttribute(handle, TextColor, ref text, sizeof(int));
    }

    /// <summary>0xRRGGBB as Windows' COLORREF (0x00BBGGRR).</summary>
    private static int ColorRef(uint rgb) => (int)((rgb & 0xFF) << 16 | (rgb & 0xFF00) | (rgb >> 16 & 0xFF));
}
