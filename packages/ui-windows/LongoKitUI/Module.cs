using System.Windows;
using System.Windows.Media;

namespace LongoKit.UI;

/// <summary>A page of a module's settings window: its tab's title and icon (a Segoe Fluent Icons glyph).</summary>
/// <param name="Fill">The page fills the window and scrolls its own parts (a chat), rather than scrolling as a whole.</param>
public sealed record ModuleTab(string Title, string Glyph, Func<FrameworkElement> Create, bool Fill = false);

/// <summary>
/// One of LongoKit's tools (Display, Shot, Mouse). It runs the same on its own, as its own app, and as a module of
/// LongoKit: the host gives it the notification area icon, the window and the shared settings.
/// </summary>
public interface ILongoModule
{
    /// <summary>"display": names its settings file and its pages.</summary>
    string Id { get; }
    /// <summary>"Longo Display".</summary>
    string Title { get; }
    /// <summary>What it does, in a few words (English, shown through L).</summary>
    string Blurb { get; }
    /// <summary>The app icon's file name in Icons (display.ico).</summary>
    string IconName { get; }

    /// <summary>Its one on/off: off, it leaves everything as Windows has it.</summary>
    bool IsOn { get; }
    void SetOn(bool on);
    /// <summary>Something shown in the menu or the window changed.</summary>
    event Action? Changed;
    /// <summary>The module wants its window on one of its tabs (a mouse's Customize goes to its buttons).</summary>
    event Action<int>? OpenTab;

    /// <summary>Starts its work (once, at launch or when LongoKit turns it on).</summary>
    void Start();
    /// <summary>Stops it and puts back what it changed (at quit, or when LongoKit turns it off).</summary>
    void Stop();

    /// <summary>The window's pages, General first. The host adds About.</summary>
    IReadOnlyList<ModuleTab> Tabs { get; }
    /// <summary>The notification area menu's body, under the header the host draws.</summary>
    FrameworkElement CreateMenu();
    /// <summary>A short status for the menu header ("2 displays", "Paused").</summary>
    string Status { get; }
}

public static class Icons
{
    /// <summary>A module's app icon, from LongoKitUI's Icons folder.</summary>
    public static ImageSource App(string name, int size = 64)
    {
        var decoder = new System.Windows.Media.Imaging.IconBitmapDecoder(
            new Uri($"pack://application:,,,/LongoKitUI;component/Icons/{name}"),
            System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
        return decoder.Frames.OrderBy(f => Math.Abs(f.PixelWidth - size)).First();
    }
}
