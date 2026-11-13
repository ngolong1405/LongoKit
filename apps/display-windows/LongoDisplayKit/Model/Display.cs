namespace LongoDisplay.Model;

/// <summary>How a display's brightness is changed.</summary>
public enum ControlMethod
{
    /// <summary>A laptop's own screen, through Windows (WMI).</summary>
    Native,
    /// <summary>A monitor that answers DDC/CI over the cable.</summary>
    Ddc,
    /// <summary>Anything else: dimmed in software only.</summary>
    Software,
}

/// <summary>How a monitor with DDC gets its brightness changed.</summary>
public enum ControlChoice { Hardware, Software }

/// <summary>A connected display. <see cref="Key"/> is stable across reconnects and restarts, and keeps its settings.</summary>
public sealed record Display(string Key, string Name, bool IsBuiltin, ControlMethod Method, int Width, int Height)
{
    /// <summary>The monitor has a DDC channel, even if software dimming was chosen for it.</summary>
    public bool HasDdc { get; init; }
    /// <summary>Where it is, in screen pixels (for the dimming over it).</summary>
    public int Left { get; init; }
    public int Top { get; init; }
}

/// <summary>What the person set for one display. Brightness, minimum and maximum are 0…1.</summary>
public sealed class DisplaySettings
{
    public double Brightness { get; set; } = 0.7;
    /// <summary>Sync maps what it follows (0…1) onto minimum…maximum.</summary>
    public double Minimum { get; set; }
    public double Maximum { get; set; } = 1;
    /// <summary>Extra software dimming below 0% brightness, 0…<see cref="MaxDim"/>.</summary>
    public double ExtraDim { get; set; }
    public ControlChoice Control { get; set; } = ControlChoice.Hardware;
    /// <summary>Speaker volume over DDC, 0…1; null until read or set, so it's never changed by itself.</summary>
    public double? Volume { get; set; }
    /// <summary>Follows in Sync; off, it keeps its own brightness.</summary>
    public bool Syncs { get; set; } = true;
    /// <summary>In Sync, how much brighter (or darker) than its range the person keeps it.</summary>
    public double SyncOffset { get; set; }

    /// <summary>The deepest extra dimming, as a fraction of the picture taken away.</summary>
    public const double MaxDim = 0.8;

    /// <summary>Brightness and extra dimming as one level: 0…1 is the backlight, below 0 darkens the picture further.</summary>
    public double Level => Brightness > 0 || ExtraDim == 0 ? Brightness : -ExtraDim;

    public void SetLevel(double value)
    {
        value = Math.Clamp(value, -MaxDim, 1);
        Brightness = Math.Max(value, 0);
        ExtraDim = Math.Max(-value, 0);
    }

    public DisplaySettings Copy() => (DisplaySettings)MemberwiseClone();
}

/// <summary>The engine's DDC writes are slow (tens of milliseconds): while one is under way only the latest value is
/// kept, so dragging a slider sends a handful instead of hundreds, and the monitor ends on the final value.</summary>
public sealed class Coalescer<T>
{
    private readonly Action<T> perform;
    private readonly object gate = new();
    private T? pending;
    private bool hasPending, busy;

    public Coalescer(Action<T> perform) => this.perform = perform;

    public void Submit(T value)
    {
        lock (gate)
        {
            pending = value;
            hasPending = true;
            if (busy) return;
            busy = true;
        }
        Task.Run(Drain);
    }

    private void Drain()
    {
        while (true)
        {
            T value;
            lock (gate)
            {
                if (!hasPending)
                {
                    busy = false;
                    return;
                }
                value = pending!;
                hasPending = false;
            }
            try { perform(value); } catch (Exception) { /* A monitor that stopped answering: the next value tries again. */ }
        }
    }
}
