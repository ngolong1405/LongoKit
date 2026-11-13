using System.Windows.Threading;
using LongoDisplay.Engine;
using LongoKit.UI;

namespace LongoDisplay.Model;

/// <summary>Manual: each display keeps the brightness set for it. Sync: external displays follow the laptop screen.</summary>
public enum BrightnessMode { Manual, Sync }

/// <summary>What's saved: the mode, on or off, and each display's settings by its key.</summary>
public sealed class DisplayState
{
    public BrightnessMode Mode { get; set; } = BrightnessMode.Manual;
    public bool IsEnabled { get; set; } = true;
    public Dictionary<string, DisplaySettings> Settings { get; set; } = new();
}

/// <summary>
/// Longo Display's state and behavior, the same as the Mac app's (AppModel.swift): the displays, each one's level,
/// Sync following the laptop screen (through each monitor's range and curve, gliding, with the person's adjustment;
/// the time of day without a laptop screen), and the volume of monitors with speakers.
/// </summary>
public sealed class DisplayModel
{
    public const string StoreName = "display";

    private readonly IDisplayEngine? engine;
    private readonly DisplayState state;
    private readonly Dictionary<string, double> glideTargets = new();
    private readonly DispatcherTimer followTimer = new() { Interval = TimeSpan.FromSeconds(0.4) };
    private readonly DispatcherTimer glideTimer = new() { Interval = TimeSpan.FromSeconds(1.0 / 15) };
    private readonly DispatcherTimer saveTimer = new() { Interval = TimeSpan.FromSeconds(0.5) };
    /// <summary>Displays first seen this session keep whatever brightness they have until it's changed.</summary>
    private readonly HashSet<string> fresh = new();
    /// <summary>The last value Sync followed (the laptop's, or the time of day's).</summary>
    private double? lastSource;

    public IReadOnlyList<Display> Displays { get; private set; } = Array.Empty<Display>();
    public event Action? Changed;

    public DisplayModel(IDisplayEngine? engine, DisplayState? state = null)
    {
        this.engine = engine;
        this.state = state ?? Store.Load<DisplayState>(StoreName);
        followTimer.Tick += (_, _) => Follow();
        glideTimer.Tick += (_, _) => GlideStep();
        saveTimer.Tick += (_, _) =>
        {
            saveTimer.Stop();
            if (engine != null) Store.Save(StoreName, this.state);
        };
        if (engine != null)
        {
            engine.BuiltinChanged += () => Follow();
            engine.DisplaysChanged += Reload;
        }
    }

    public BrightnessMode Mode
    {
        get => state.Mode;
        set
        {
            if (state.Mode == value) return;
            state.Mode = value;
            lastSource = null;
            Saved();
            Follow();
        }
    }

    /// <summary>Off, the app leaves displays alone: no Sync, no dimming.</summary>
    public bool IsEnabled
    {
        get => state.IsEnabled;
        set
        {
            if (state.IsEnabled == value) return;
            state.IsEnabled = value;
            if (value)
            {
                lastSource = null;
                foreach (var display in Displays) Apply(display);
                Follow();
            }
            else
            {
                engine?.ClearDimming();
            }
            Saved();
        }
    }

    public Display? Builtin => Displays.FirstOrDefault(d => d.IsBuiltin);
    public IEnumerable<Display> Externals => Displays.Where(d => !d.IsBuiltin);

    public DisplaySettings Settings(Display display) => state.Settings.TryGetValue(display.Key, out var value) ? value : new DisplaySettings();

    public void Start()
    {
        Reload();
        followTimer.Start();
    }

    public void Stop()
    {
        followTimer.Stop();
        glideTimer.Stop();
        engine?.ClearDimming();
        if (saveTimer.IsEnabled)
        {
            saveTimer.Stop();
            if (engine != null) Store.Save(StoreName, state);
        }
    }

    /// <summary>For tests and snapshots: these displays and settings, with no hardware.</summary>
    public void Simulate(IReadOnlyList<Display> displays, Dictionary<string, DisplaySettings> settings)
    {
        Displays = displays;
        state.Settings = settings;
        Changed?.Invoke();
    }

    /// <summary>The displays connected now. A new one starts from what it shows; a known one gets its brightness back.</summary>
    public void Reload()
    {
        if (engine == null) return;
        Displays = engine.List().OrderBy(d => d.IsBuiltin ? 0 : 1).ThenBy(d => d.Name).ToList();
        foreach (var display in Displays)
        {
            if (!state.Settings.ContainsKey(display.Key))
            {
                state.Settings[display.Key] = new DisplaySettings { Brightness = display.IsBuiltin ? engine.BuiltinBrightness ?? 1 : 1 };
                fresh.Add(display.Key);
                _ = ReadFromMonitor(display);
            }
            else if (IsEnabled && display.Method != ControlMethod.Native && !fresh.Contains(display.Key))
            {
                Apply(display);
            }
            if (display.Method == ControlMethod.Ddc && Settings(display).Volume == null) _ = ReadVolume(display);
        }
        // A display that just connected joins Sync right away.
        lastSource = null;
        Follow();
        Changed?.Invoke();
    }

    private async Task ReadFromMonitor(Display display)
    {
        if (engine == null || display.Method != ControlMethod.Ddc) return;
        if (await engine.ReadBrightness(display) is not { } value || !fresh.Contains(display.Key)) return;
        state.Settings[display.Key].Brightness = value;
        Changed?.Invoke();
    }

    private async Task ReadVolume(Display display)
    {
        if (engine == null || await engine.ReadVolume(display) is not { } value) return;
        state.Settings[display.Key].Volume = value;
        Saved();
    }

    // MARK: - Levels

    /// <summary>How low a display's level goes: below 0 is extra dimming, except where brightness is already done in
    /// software and going lower would only repeat it.</summary>
    public (double Lowest, double Highest) LevelRange(Display display) =>
        display.Method == ControlMethod.Software || Settings(display).Control == ControlChoice.Software && display.Method == ControlMethod.Ddc
            ? (0, 1)
            : (-DisplaySettings.MaxDim, 1);

    /// <summary>Brightness and extra dimming as one level. A display following in Sync, set by hand, keeps following,
    /// this much brighter or darker than its range says.</summary>
    public void SetLevel(Display display, double value)
    {
        var (lowest, highest) = LevelRange(display);
        value = Math.Clamp(value, lowest, highest);
        if (FollowsSync(display))
        {
            glideTargets.Remove(display.Key);
            var baseline = SyncTarget(display, withOffset: false);
            Update(display, s =>
            {
                s.SyncOffset = value - baseline;
                s.SetLevel(value);
            });
            return;
        }
        Update(display, s => s.SetLevel(value));
        // In Sync the others follow the laptop screen right away, not at the next check.
        if (display.IsBuiltin && Mode == BrightnessMode.Sync)
        {
            lastSource = null;
            Follow();
        }
    }

    /// <summary>Presets set every display at once; in Sync the laptop screen leads and the others follow it.</summary>
    public void ApplyPreset(double value)
    {
        if (Mode == BrightnessMode.Sync && Builtin is { } builtin)
        {
            SetLevel(builtin, value);
            foreach (var display in Externals.Where(d => !FollowsSync(d))) SetLevel(display, value);
            return;
        }
        foreach (var display in Displays) SetLevel(display, value);
    }

    public void SetVolume(Display display, double value)
    {
        Update(display, s => s.Volume = Math.Clamp(value, 0, 1), apply: false);
        engine?.SetVolume(display, value);
    }

    public void SetControl(Display display, ControlChoice choice)
    {
        Update(display, s =>
        {
            s.Control = choice;
            if (choice == ControlChoice.Software && s.ExtraDim > 0) s.SetLevel(0);
        });
    }

    /// <summary>Back to the default range, control and dimming; the brightness it's at stays. In Sync it lines up again.</summary>
    public void ResetDisplay(Display display)
    {
        var current = Settings(display);
        state.Settings[display.Key] = new DisplaySettings { Brightness = current.Brightness, Volume = current.Volume };
        Apply(display);
        LineUp(display);
        Saved();
    }

    private void Update(Display display, Action<DisplaySettings> change, bool apply = true)
    {
        fresh.Remove(display.Key);
        if (!state.Settings.TryGetValue(display.Key, out var value)) state.Settings[display.Key] = value = new DisplaySettings();
        change(value);
        if (apply) Apply(display);
        Saved();
    }

    private void Apply(Display display)
    {
        if (IsEnabled) engine?.Apply(display, Settings(display));
    }

    private void Saved()
    {
        // Written once things settle, not on every step of a drag or a glide.
        saveTimer.Stop();
        saveTimer.Start();
        Changed?.Invoke();
    }

    // MARK: - Sync

    /// <summary>Whether an external display follows in Sync.</summary>
    public bool FollowsSync(Display display) => Mode == BrightnessMode.Sync && !display.IsBuiltin && Settings(display).Syncs;

    /// <summary>What Sync follows: the laptop screen's brightness, or without one (lid closed, a desktop PC) the time of day.</summary>
    public double SyncSource => Builtin is { } builtin ? Settings(builtin).Brightness : SyncMath.Daylight(SyncMath.Hour(DateTime.Now));

    /// <summary>Where a display following in Sync goes now, with or without the person's adjustment.</summary>
    public double SyncTarget(Display display, bool withOffset = true)
    {
        var value = Settings(display).Copy();
        if (!withOffset) value.SyncOffset = 0;
        return SyncMath.Target(SyncSource, value, display.Method, LevelRange(display).Lowest);
    }

    public void SetSyncRange(Display display, double minimum, double maximum)
    {
        Update(display, s =>
        {
            s.Minimum = Math.Min(minimum, maximum);
            s.Maximum = Math.Max(minimum, maximum);
        }, apply: false);
        LineUp(display);
    }

    /// <summary>The Sync switch on a display's page: on, it follows (turning Sync on if it was off), from its range.</summary>
    public void SetSyncs(Display display, bool on)
    {
        Update(display, s =>
        {
            s.Syncs = on;
            if (on) s.SyncOffset = 0;
        }, apply: false);
        if (on && Mode != BrightnessMode.Sync) Mode = BrightnessMode.Sync;
        else if (on) LineUp(display);
    }

    /// <summary>Forgets the person's adjustment: it follows its range again.</summary>
    public void ResetSyncOffset(Display display)
    {
        Update(display, s => s.SyncOffset = 0, apply: false);
        LineUp(display);
    }

    /// <summary>A following display, put where Sync says at once (its range just changed, it just joined).</summary>
    private void LineUp(Display display)
    {
        if (!FollowsSync(display) || !IsEnabled) return;
        glideTargets.Remove(display.Key);
        var target = SyncTarget(display);
        Update(display, s => s.SetLevel(target));
    }

    /// <summary>Tracks the laptop screen (its keys, and Windows following the light), or the time of day without one; in
    /// Sync the external displays follow.</summary>
    public void Follow()
    {
        if (Builtin is { } builtin && engine?.BuiltinBrightness is { } value)
        {
            if (lastSource is { } last && Math.Abs(last - value) <= 0.004) return;
            lastSource = value;
            if (value > 0 && Settings(builtin).ExtraDim > 0) Update(builtin, s => s.SetLevel(value));
            else if (state.Settings.TryGetValue(builtin.Key, out var settings)) settings.Brightness = value;
        }
        else if (Builtin == null)
        {
            var daylight = SyncSource;
            if (lastSource is { } last && Math.Abs(last - daylight) <= 0.004) return;
            lastSource = daylight;
        }
        if (Mode != BrightnessMode.Sync || !IsEnabled) return;
        foreach (var display in Externals.Where(d => Settings(d).Syncs))
        {
            var target = SyncTarget(display);
            if (!glideTargets.ContainsKey(display.Key) && Math.Abs(target - Settings(display).Level) < SyncMath.Deadband) continue;
            glideTargets[display.Key] = target;
        }
        if (glideTargets.Count > 0 && !glideTimer.IsEnabled) glideTimer.Start();
        Changed?.Invoke();
    }

    /// <summary>One step of every glide; the timer stops once they've all arrived.</summary>
    private void GlideStep()
    {
        foreach (var (key, target) in glideTargets.ToList())
        {
            var display = Displays.FirstOrDefault(d => d.Key == key);
            if (!IsEnabled || display == null || !FollowsSync(display))
            {
                glideTargets.Remove(key);
                continue;
            }
            var next = SyncMath.Glide(Settings(display).Level, target);
            Update(display, s => s.SetLevel(next));
            if (next == target) glideTargets.Remove(key);
        }
        if (glideTargets.Count == 0) glideTimer.Stop();
    }
}
