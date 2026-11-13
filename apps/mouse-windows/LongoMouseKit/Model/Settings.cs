namespace LongoMouse.Model;

/// <summary>The buttons Windows tells apps about besides left and right.</summary>
public enum MouseButton { Middle, Back, Forward }

/// <summary>What a button does to call an action.</summary>
public enum Gesture { Click, DoubleClick, Hold, Drag, Scroll }

/// <summary>Everything a gesture can do, as on the Mac, with Windows' own equivalents.</summary>
public enum MouseAction
{
    None,
    // Windows & desktops
    TaskView, ShowDesktop, Start, DesktopLeft, DesktopRight,
    // Navigation
    Back, Forward,
    // Clicks
    PrimaryClick, PrimaryDoubleClick, SecondaryClick, MiddleClick,
    // Keys
    Shortcut, PlayPause, NextTrack, PreviousTrack, VolumeUp, VolumeDown, Mute,
    // While dragging
    DragDesktops, DragTaskView, DragScroll,
    // While scrolling
    ScrollZoom, ScrollDesktops, ScrollHorizontal,
}

/// <summary>A key combination to press, like Ctrl+Shift+T. <see cref="Key"/> is a Windows virtual-key code.</summary>
public sealed record KeyCombo(int Key, bool Control, bool Alt, bool Shift, bool Windows)
{
    public string Name
    {
        get
        {
            var parts = new List<string>();
            if (Control) parts.Add("Ctrl");
            if (Alt) parts.Add("Alt");
            if (Shift) parts.Add("Shift");
            if (Windows) parts.Add("Win");
            parts.Add(KeyName(Key));
            return string.Join("+", parts);
        }
    }

    private static string KeyName(int key) => key switch
    {
        >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A => ((char)key).ToString(),
        >= 0x70 and <= 0x87 => "F" + (key - 0x6F),
        0x25 => "←", 0x26 => "↑", 0x27 => "→", 0x28 => "↓",
        0x20 => "Space", 0x0D => "Enter", 0x09 => "Tab", 0x1B => "Esc", 0x08 => "Backspace", 0x2E => "Delete",
        0x21 => "Page Up", 0x22 => "Page Down", 0x24 => "Home", 0x23 => "End",
        _ => $"0x{key:X2}",
    };
}

/// <summary>One gesture of one button, and what it does.</summary>
public sealed class Binding
{
    public MouseButton Button { get; set; }
    public Gesture Gesture { get; set; }
    public MouseAction Action { get; set; }
    public KeyCombo? Shortcut { get; set; }
}

/// <summary>The mouse wheel, as on the Mac (ScrollSettings).</summary>
public sealed class ScrollSettings
{
    /// <summary>Classic (Windows' own) or natural (content follows the finger, as on a phone).</summary>
    public bool Natural { get; set; }
    /// <summary>Each notch glides and eases out.</summary>
    public bool Smooth { get; set; } = true;
    /// <summary>How long a glide takes: 200 ms (0) to 1000 ms (1).</summary>
    public double Smoothness { get; set; } = 0.75;
    /// <summary>Scroll speed applies.</summary>
    public bool CustomSpeed { get; set; } = true;
    /// <summary>0.5× to 2×.</summary>
    public double Speed { get; set; } = 1;
    /// <summary>Shift + wheel scrolls sideways.</summary>
    public bool ShiftSideways { get; set; } = true;
    /// <summary>Ctrl + Shift + wheel goes back and forward.</summary>
    public bool BackForward { get; set; } = true;

    public ScrollSettings Copy() => (ScrollSettings)MemberwiseClone();
}

/// <summary>A mouse seen on this PC: its name, and its own buttons or scrolling if it has them.</summary>
public sealed class DeviceProfile
{
    public string Product { get; set; } = "";
    public string Manufacturer { get; set; } = "";
    public string Connection { get; set; } = "";
    public string? CustomName { get; set; }
    public DateTime LastSeen { get; set; }
    /// <summary>Its own buttons; otherwise the shared ones.</summary>
    public bool OwnButtons { get; set; }
    public List<Binding> Bindings { get; set; } = new();
    /// <summary>Its own scrolling; null follows the shared one.</summary>
    public ScrollSettings? Scroll { get; set; }

    public string Name => string.IsNullOrWhiteSpace(CustomName) ? (string.IsNullOrWhiteSpace(Product) ? "Mouse" : Product) : CustomName!;
}

/// <summary>Everything saved.</summary>
public sealed class MouseState
{
    public bool IsEnabled { get; set; } = true;
    /// <summary>Double-Click Fix: a second click of the left or right button this soon after a release is ignored.</summary>
    public bool ClickGuard { get; set; }
    public int ClickGuardMs { get; set; } = 60;
    /// <summary>The settings of the mouse in use (the one that moved last), when it has its own.</summary>
    public bool AutoSwitch { get; set; } = true;
    public List<Binding> Bindings { get; set; } = Defaults();
    public ScrollSettings Scroll { get; set; } = new();
    public Dictionary<string, DeviceProfile> Devices { get; set; } = new();

    /// <summary>Back and forward on the side buttons, as browsers expect.</summary>
    public static List<Binding> Defaults() => new()
    {
        new() { Button = MouseButton.Back, Gesture = Gesture.Click, Action = MouseAction.Back },
        new() { Button = MouseButton.Forward, Gesture = Gesture.Click, Action = MouseAction.Forward },
    };
}

/// <summary>What the engine follows right now: the buttons and the wheel of the mouse in use.</summary>
public sealed record EngineSettings(bool Enabled, IReadOnlyList<Binding> Bindings, ScrollSettings Scroll, bool ClickGuard, int ClickGuardMs)
{
    public static readonly EngineSettings Off = new(false, Array.Empty<Binding>(), new ScrollSettings(), false, 60);
}
