using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace LongoKit.UI;

/// <summary>Light, dark, or as Windows is set.</summary>
public enum Appearance { System, Dark, Light }

/// <summary>
/// LongoKit's colors and fonts, the same as the macOS apps' (packages/ui-macos Components.swift). Every color is an
/// application resource under its name ("Solar", "Text"...), so views refer to it with SetResourceReference or
/// DynamicResource and follow a change of appearance at once.
/// </summary>
public static class Theme
{
    // (dark, light) pairs, with an opacity where the Mac's has one.
    private static readonly Dictionary<string, (uint Dark, uint Light, double DarkOpacity, double LightOpacity)> Palette = new()
    {
        ["Solar"] = (0xFF6B35, 0xEE5A22, 1, 1),
        ["SolarLight"] = (0xFFA26B, 0xD94814, 1, 1),
        ["Violet"] = (0x8B5CF6, 0x7C3AED, 1, 1),
        ["VioletLight"] = (0xA78BFA, 0x6D28D9, 1, 1),
        ["Emerald"] = (0x10B981, 0x059669, 1, 1),
        ["Amber"] = (0xF59E0B, 0xD97706, 1, 1),
        ["Danger"] = (0xEF4444, 0xDC2626, 1, 1),
        ["Canvas"] = (0x0B0C10, 0xF5F6F8, 1, 1),
        ["CanvasTop"] = (0x121319, 0xFFFFFF, 1, 1),
        ["Island"] = (0x1A1B22, 0xFFFFFF, 1, 1),
        ["Well"] = (0x0C0E13, 0xE9EBEF, 0.8, 1),
        ["Hover"] = (0x242632, 0xEDF0F5, 1, 1),
        ["Slate"] = (0x2F3242, 0xE1E5ED, 1, 1),
        ["Chrome"] = (0x000000, 0x000000, 0.25, 0.03),
        ["PopoverTop"] = (0x1B1A24, 0xFFFFFF, 1, 1),
        ["SegmentTrack"] = (0x0C0E13, 0xE6E8EC, 0.8, 1),
        ["SegmentSelected"] = (0x2F3242, 0xFFFFFF, 1, 1),
        ["Hairline"] = (0xFFFFFF, 0x000000, 0.08, 0.08),
        ["BorderProminent"] = (0xFFFFFF, 0x000000, 0.16, 0.14),
        ["Tint04"] = (0xFFFFFF, 0x000000, 0.04, 0.04),
        ["Tint10"] = (0xFFFFFF, 0x000000, 0.10, 0.10),
        ["Text"] = (0xF3F4F6, 0x111827, 1, 1),
        ["TextSecondary"] = (0xD1D5DB, 0x374151, 1, 1),
        ["TextMuted"] = (0x9CA3AF, 0x4B5563, 1, 1),
        ["TextFaint"] = (0x6B7280, 0x9CA3AF, 1, 1),
        ["Shadow"] = (0x000000, 0x000000, 0.35, 0.07),
    };

    public static readonly FontFamily UI = Font("Geist");
    public static readonly FontFamily Display = Font("Space Grotesk");
    public static readonly FontFamily Mono = Font("JetBrains Mono");
    /// <summary>Windows' own icon font: Segoe Fluent Icons on Windows 11, Segoe MDL2 Assets before it.</summary>
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    private static FontFamily Font(string name) =>
        new(new Uri("pack://application:,,,/LongoKitUI;component/Fonts/"), "./#" + name + ", Segoe UI");

    public static bool IsDark { get; private set; } = true;

    /// <summary>Whether Windows is set to dark for apps.</summary>
    public static bool SystemIsDark
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is not int light || light == 0;
        }
    }

    /// <summary>Puts the colors for <paramref name="appearance"/> into the application's resources.</summary>
    public static void Apply(Appearance appearance)
    {
        IsDark = appearance switch { Appearance.Dark => true, Appearance.Light => false, _ => SystemIsDark };
        var resources = Application.Current.Resources;
        if (!resources.MergedDictionaries.Any(d => d.Source?.OriginalString.Contains("LongoKitUI") == true))
        {
            resources.MergedDictionaries.Add(new ResourceDictionary
            {
                Source = new Uri("pack://application:,,,/LongoKitUI;component/Styles.xaml"),
            });
        }
        foreach (var (name, pair) in Palette)
        {
            resources[name] = Brush(IsDark ? pair.Dark : pair.Light, IsDark ? pair.DarkOpacity : pair.LightOpacity);
            resources[name + "Color"] = Color(IsDark ? pair.Dark : pair.Light, IsDark ? pair.DarkOpacity : pair.LightOpacity);
        }
        resources["White"] = Brushes.White;
        resources["Accent"] =new LinearGradientBrush(Color(0xFF6B35, 1), Color(0x8B5CF6, 1), 0) { Opacity = 1 }.Frozen();
        resources["AccentDiagonal"] = new LinearGradientBrush(Color(0xFF6B35, 1), Color(0x8B5CF6, 1), new Point(0, 0), new Point(1, 1)).Frozen();
        resources["UIFont"] = UI;
        resources["DisplayFont"] = Display;
        resources["MonoFont"] = Mono;
        resources["IconFont"] = Icons;
    }

    public static Color Color(uint rgb, double opacity = 1) =>
        System.Windows.Media.Color.FromArgb((byte)Math.Round(opacity * 255), (byte)(rgb >> 16), (byte)(rgb >> 8 & 0xFF), (byte)(rgb & 0xFF));

    public static SolidColorBrush Brush(uint rgb, double opacity = 1) => new SolidColorBrush(Color(rgb, opacity)).Frozen();

    private static T Frozen<T>(this T freezable) where T : Freezable
    {
        freezable.Freeze();
        return freezable;
    }
}
