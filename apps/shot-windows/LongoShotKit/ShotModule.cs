using System.Diagnostics;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LongoKit.UI;
using LongoShot.Capture;
using LongoShot.Engine;
using LongoShot.Model;
using LongoShot.UI;

namespace LongoShot;

/// <summary>What each shortcut does.</summary>
public enum ShotAction { CaptureArea, CaptureScreen, CaptureText }

/// <summary>Longo Shot as a module: on its own (LongoShot.exe) or in LongoKit.</summary>
public sealed class ShotModule : ILongoModule, ISampleData
{
    public static readonly IReadOnlyDictionary<ShotAction, Hotkey> Shortcuts = new Dictionary<ShotAction, Hotkey>
    {
        [ShotAction.CaptureArea] = Hotkey.AltShift('1'),
        [ShotAction.CaptureScreen] = Hotkey.AltShift('2'),
        [ShotAction.CaptureText] = Hotkey.AltShift('3'),
    };

    private ShotModel model = new(false, new ShotState());
    private Hotkeys? hotkeys;
    private CaptureSession? session;

    public ShotModel Model => model;
    /// <summary>Shortcuts another app holds.</summary>
    public HashSet<ShotAction> Taken { get; } = new();

    public string Id => "shot";
    public string Title => "Longo Shot";
    public string Blurb => "Screenshots & copying text on screen";
    public string IconName => "shot.ico";
    public bool IsOn => model.State.IsEnabled;
    public event Action? Changed;
    public event Action<int>? OpenTab { add { } remove { } }

    public ShotModule() => Localizer.Register(Strings.Vietnamese);

    public string Status => !IsOn ? "" : Taken.Count > 0 ? Localizer.L("A shortcut is taken") : Localizer.L("Ready");

    public void SetOn(bool on)
    {
        model.Change(s => s.IsEnabled = on);
        // Off, its shortcuts let go so other apps can use them; the menu still captures.
        Register();
    }

    public void Start()
    {
        Use(new ShotModel(true));
        hotkeys = new Hotkeys();
        session = new CaptureSession(model, ReadText);
        Register();
        // Ready before the first capture: the capture windows made once the app is idle.
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () => session.Prepare());
    }

    public void Stop()
    {
        model.Flush();
        hotkeys?.Dispose();
        session?.Close();
    }

    private void Register()
    {
        if (hotkeys == null) return;
        hotkeys.Clear();
        Taken.Clear();
        if (IsOn)
        {
            foreach (var (action, hotkey) in Shortcuts)
                if (!hotkeys.Add(hotkey, () => Run(action))) Taken.Add(action);
        }
        Changed?.Invoke();
    }

    /// <summary>Starts a capture. From the menu, the menu goes first, so it isn't in the picture.</summary>
    public void Run(ShotAction action, bool fromMenu = false)
    {
        if (session == null) return;
        if (fromMenu)
        {
            foreach (Window window in Application.Current.Windows)
                if (window.GetType().Name == "MenuWindow") window.Hide();
            var wait = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
            wait.Tick += (_, _) =>
            {
                wait.Stop();
                Run(action);
            };
            wait.Start();
            return;
        }
        switch (action)
        {
            case ShotAction.CaptureArea: session.PickArea(forText: false); break;
            case ShotAction.CaptureScreen: session.WholeScreen(); break;
            case ShotAction.CaptureText: session.PickArea(forText: true); break;
        }
    }

    private void ReadText(BitmapSource picture) => new TextWindow(picture, model).Show();

    public void OpenFolder()
    {
        Directory.CreateDirectory(model.State.Folder);
        Process.Start(new ProcessStartInfo(model.State.Folder) { UseShellExecute = true });
    }

    public void UseSampleData() => Use(new ShotModel(false, new ShotState()));

    public IReadOnlyList<(string Name, int Tab, Action Open)> SamplePages => Array.Empty<(string, int, Action)>();

    private void Use(ShotModel next)
    {
        model.Changed -= OnChanged;
        model = next;
        model.Changed += OnChanged;
        OnChanged();
    }

    private void OnChanged() => Changed?.Invoke();

    public IReadOnlyList<ModuleTab> Tabs => new[]
    {
        new ModuleTab(Localizer.L("General"), "\uE713", () => ShotPages.General(this)),
        new ModuleTab(Localizer.L("Shortcuts"), "\uE765", () => ShotPages.Shortcuts(this)),
    };

    public FrameworkElement CreateMenu() => ShotPages.Menu(this);
}
