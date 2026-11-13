using System.Windows;
using LongoKit.UI;
using LongoMouse.Engine;
using LongoMouse.Model;
using LongoMouse.UI;

namespace LongoMouse;

/// <summary>Longo Mouse as a module: on its own (LongoMouse.exe) or in LongoKit.</summary>
public sealed class MouseModule : ILongoModule, ISampleData
{
    private MouseModel model = new(null, null, new MouseState());
    private MouseEngine? engine;
    private Mice? mice;

    public MouseModel Model => model;
    /// <summary>The mouse whose settings the Buttons and Scrolling pages show; null for all mice.</summary>
    public string? Selected { get; private set; }

    public string Id => "mouse";
    public string Title => "Longo Mouse";
    public string Blurb => "Buttons, gestures & smooth scrolling";
    public string IconName => "mouse.ico";
    public bool IsOn => model.IsEnabled;
    public event Action? Changed;
    public event Action<int>? OpenTab;

    public MouseModule() => Localizer.Register(Strings.Vietnamese);

    public string Status => !model.IsEnabled ? ""
        : model.InUse is { } inUse ? model.NameOf(inUse)
        : model.Connected.Count == 0 ? Localizer.L("No mouse found.") : Localizer.L("On");

    public void SetOn(bool on) => model.IsEnabled = on;

    public void Start()
    {
        engine = new MouseEngine();
        mice = new Mice();
        Use(new MouseModel(engine, mice));
    }

    public void Stop()
    {
        model.Flush();
        engine?.Dispose();
        mice?.Dispose();
    }

    public void UseSampleData()
    {
        Use(new MouseModel(null, null, new MouseState()));
        model.Simulate(new[]
        {
            new MouseDevice("046D:B034", "MX Master 3S", "Logitech", "Bluetooth"),
            new MouseDevice("1532:0099", "DeathAdder V3", "Razer", "USB"),
        }, "046D:B034");
        model.SetOwnScroll("1532:0099", true);
        model.SetAction(null, MouseButton.Middle, Gesture.Drag, MouseAction.DragScroll);
        model.SetAction(null, MouseButton.Forward, Gesture.Hold, MouseAction.TaskView);
        model.SetAction(null, MouseButton.Back, Gesture.Scroll, MouseAction.ScrollZoom);
        model.SetAction(null, MouseButton.Middle, Gesture.DoubleClick, MouseAction.Shortcut, new KeyCombo('T', true, false, true, false));
    }

    public IReadOnlyList<(string Name, int Tab, Action Open)> SamplePages => new (string, int, Action)[]
    {
        ("razer-scrolling", 1, () => Select("1532:0099")),
        ("razer-buttons", 2, () => Select("1532:0099")),
    };

    private void Use(MouseModel next)
    {
        model.Changed -= OnChanged;
        model = next;
        model.Changed += OnChanged;
        OnChanged();
    }

    private void OnChanged() => Changed?.Invoke();

    public void Select(string? key)
    {
        Selected = key;
        Changed?.Invoke();
    }

    public void ShowTab(int tab) => OpenTab?.Invoke(tab);

    public IReadOnlyList<ModuleTab> Tabs => new[]
    {
        new ModuleTab(Localizer.L("General"), "\uE713", () => MousePages.General(this)),
        new ModuleTab(Localizer.L("Scrolling"), "\uE8CB", () => MousePages.Scrolling(this)),
        new ModuleTab(Localizer.L("Buttons"), "\uE962", () => MousePages.Buttons(this)),
        new ModuleTab(Localizer.L("Mice"), "\uE772", () => MousePages.Mice(this)),
    };

    public FrameworkElement CreateMenu() => MousePages.Menu(this);
}
