using System.Windows.Threading;
using LongoKit.UI;
using LongoMouse.Engine;

namespace LongoMouse.Model;

/// <summary>
/// Longo Mouse's state, the same as the Mac app's (AppModel.swift): the shared buttons and wheel, each mouse's own if
/// it has them, which one is in use, and what the engine follows. A profile key of null is the shared settings.
/// </summary>
public sealed class MouseModel
{
    public const string StoreName = "mouse";

    private readonly MouseState state;
    private readonly MouseEngine? engine;
    private readonly Mice? mice;
    private readonly DispatcherTimer saveTimer = new() { Interval = TimeSpan.FromSeconds(0.5) };
    private IReadOnlyList<MouseDevice> sample = Array.Empty<MouseDevice>();
    private string? sampleInUse;

    public event Action? Changed;

    public MouseModel(MouseEngine? engine, Mice? mice, MouseState? state = null)
    {
        this.engine = engine;
        this.mice = mice;
        this.state = state ?? Store.Load<MouseState>(StoreName);
        saveTimer.Tick += (_, _) =>
        {
            saveTimer.Stop();
            if (engine != null) Store.Save(StoreName, this.state);
        };
        if (mice != null)
        {
            mice.Changed += () =>
            {
                Remember();
                Push();
                Changed?.Invoke();
            };
            Remember();
        }
        Push();
    }

    public IReadOnlyList<MouseDevice> Connected => mice?.Connected ?? sample;
    public string? InUse => mice?.InUse ?? sampleInUse;
    public IReadOnlyDictionary<string, DeviceProfile> Devices => state.Devices;

    /// <summary>For tests and snapshots: these mice, this one in use.</summary>
    public void Simulate(IReadOnlyList<MouseDevice> devices, string? inUse)
    {
        sample = devices;
        sampleInUse = inUse;
        Remember();
        Changed?.Invoke();
    }

    public bool IsEnabled
    {
        get => state.IsEnabled;
        set => Change(() => state.IsEnabled = value);
    }

    public bool ClickGuard
    {
        get => state.ClickGuard;
        set => Change(() => state.ClickGuard = value);
    }

    public int ClickGuardMs
    {
        get => state.ClickGuardMs;
        set => Change(() => state.ClickGuardMs = Math.Clamp(value, 20, 150));
    }

    public bool AutoSwitch
    {
        get => state.AutoSwitch;
        set => Change(() => state.AutoSwitch = value);
    }

    /// <summary>A mouse seen on this PC is kept, with its name and when it was last there.</summary>
    private void Remember()
    {
        foreach (var device in Connected)
        {
            if (!state.Devices.TryGetValue(device.Key, out var profile)) state.Devices[device.Key] = profile = new DeviceProfile();
            profile.Product = device.Product;
            profile.Manufacturer = device.Manufacturer;
            profile.Connection = device.Connection;
            profile.LastSeen = DateTime.Now;
        }
    }

    public string NameOf(string key) => state.Devices.TryGetValue(key, out var profile) ? profile.Name : "Mouse";

    // MARK: - Profiles

    /// <summary>The scrolling a profile edits: a mouse's own, or the shared one.</summary>
    public ScrollSettings Scroll(string? key) =>
        key != null && state.Devices.TryGetValue(key, out var profile) && profile.Scroll != null ? profile.Scroll : state.Scroll;

    public bool HasOwnScroll(string key) => state.Devices.TryGetValue(key, out var profile) && profile.Scroll != null;

    public bool HasOwnButtons(string key) => state.Devices.TryGetValue(key, out var profile) && profile.OwnButtons;

    /// <summary>The buttons a profile edits.</summary>
    public IReadOnlyList<Binding> Bindings(string? key) =>
        key != null && state.Devices.TryGetValue(key, out var profile) && profile.OwnButtons ? profile.Bindings : state.Bindings;

    public void SetScroll(string? key, Action<ScrollSettings> change) => Change(() => change(Scroll(key)));

    /// <summary>A mouse's own scrolling starts as a copy of the shared one; off, it follows the shared one again.</summary>
    public void SetOwnScroll(string key, bool own) => Change(() =>
    {
        if (state.Devices.TryGetValue(key, out var profile)) profile.Scroll = own ? state.Scroll.Copy() : null;
    });

    public void SetOwnButtons(string key, bool own) => Change(() =>
    {
        if (!state.Devices.TryGetValue(key, out var profile)) return;
        profile.OwnButtons = own;
        if (own) profile.Bindings = state.Bindings.Select(b => new Binding { Button = b.Button, Gesture = b.Gesture, Action = b.Action, Shortcut = b.Shortcut }).ToList();
    });

    /// <summary>What a gesture does in a profile (None removes it).</summary>
    public void SetAction(string? key, MouseButton button, Gesture gesture, MouseAction action, KeyCombo? shortcut = null) => Change(() =>
    {
        var list = key != null && state.Devices.TryGetValue(key, out var profile) && profile.OwnButtons ? profile.Bindings : state.Bindings;
        list.RemoveAll(b => b.Button == button && b.Gesture == gesture);
        if (action != MouseAction.None) list.Add(new Binding { Button = button, Gesture = gesture, Action = action, Shortcut = shortcut });
    });

    public MouseAction ActionOf(string? key, MouseButton button, Gesture gesture) =>
        Bindings(key).FirstOrDefault(b => b.Button == button && b.Gesture == gesture)?.Action ?? MouseAction.None;

    public KeyCombo? ShortcutOf(string? key, MouseButton button, Gesture gesture) =>
        Bindings(key).FirstOrDefault(b => b.Button == button && b.Gesture == gesture)?.Shortcut;

    public void Rename(string key, string name) => Change(() =>
    {
        if (state.Devices.TryGetValue(key, out var profile)) profile.CustomName = string.IsNullOrWhiteSpace(name) ? null : name.Trim();
    });

    public void Forget(string key) => Change(() => state.Devices.Remove(key));

    /// <summary>Back to the defaults: the shared buttons and wheel, on, no Double-Click Fix. Mice keep their names.</summary>
    public void RestoreDefaults() => Change(() =>
    {
        state.IsEnabled = true;
        state.ClickGuard = false;
        state.ClickGuardMs = 60;
        state.AutoSwitch = true;
        state.Bindings = MouseState.Defaults();
        state.Scroll = new ScrollSettings();
        foreach (var profile in state.Devices.Values)
        {
            profile.OwnButtons = false;
            profile.Bindings.Clear();
            profile.Scroll = null;
        }
    });

    // MARK: - The engine

    /// <summary>The mouse whose settings are in force: the one in use, if switching with it is on.</summary>
    public string? Following => state.AutoSwitch ? InUse : null;

    /// <summary>What the engine follows now.</summary>
    public EngineSettings Effective =>
        new(state.IsEnabled, Bindings(Following).ToList(), Scroll(Following).Copy(), state.ClickGuard, state.ClickGuardMs);

    private void Push()
    {
        if (engine != null) engine.Settings = Effective;
    }

    private void Change(Action change)
    {
        change();
        Push();
        saveTimer.Stop();
        saveTimer.Start();
        Changed?.Invoke();
    }

    public void Flush()
    {
        if (!saveTimer.IsEnabled) return;
        saveTimer.Stop();
        if (engine != null) Store.Save(StoreName, state);
    }
}
