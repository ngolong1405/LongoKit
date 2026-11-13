using LongoDisplay.Model;

namespace LongoDisplay.Engine;

/// <summary>What the model asks of the hardware. The Windows one talks to the monitors; tests and snapshots go without.</summary>
public interface IDisplayEngine : IDisposable
{
    /// <summary>The displays connected now.</summary>
    IReadOnlyList<Display> List();
    /// <summary>The laptop screen's brightness (0…1) as last read, or null without one.</summary>
    double? BuiltinBrightness { get; }
    /// <summary>The laptop screen's brightness changed (its keys, or Windows following the light).</summary>
    event Action? BuiltinChanged;
    /// <summary>A display was connected, removed or moved.</summary>
    event Action? DisplaysChanged;
    /// <summary>What a monitor shows now over DDC, read in the background; null if it doesn't answer.</summary>
    Task<double?> ReadBrightness(Display display);
    Task<double?> ReadVolume(Display display);
    /// <summary>Puts a display's settings on it: its backlight, and any dimming over it.</summary>
    void Apply(Display display, DisplaySettings settings);
    void SetVolume(Display display, double volume);
    /// <summary>Takes away any dimming (paused, or quitting).</summary>
    void ClearDimming();
}
