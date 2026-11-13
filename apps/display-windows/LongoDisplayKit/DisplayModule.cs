using System.Windows;
using LongoDisplay.Engine;
using LongoDisplay.Model;
using LongoDisplay.UI;
using LongoKit.UI;

namespace LongoDisplay;

/// <summary>Longo Display as a module: on its own (LongoDisplay.exe) or in LongoKit.</summary>
public sealed class DisplayModule : ILongoModule, ISampleData
{
    private DisplayModel model = new(null, new DisplayState());

    public DisplayModel Model => model;
    /// <summary>The display whose page is open on the Displays tab.</summary>
    public string? OpenDisplay { get; private set; }

    public string Id => "display";
    public string Title => "Longo Display";
    public string Blurb => "Brightness & volume for every display";
    public string IconName => "display.ico";
    public bool IsOn => model.IsEnabled;
    public event Action? Changed;

    public DisplayModule() => Localizer.Register(Strings.Vietnamese);

    public string Status => !model.IsEnabled ? "" : model.Mode == BrightnessMode.Sync
        ? Localizer.L("Sync")
        : model.Displays.Count == 1 ? Localizer.L("1 display") : Localizer.L("{0} displays", model.Displays.Count);

    public void SetOn(bool on) => model.IsEnabled = on;

    public void Start()
    {
        Use(new DisplayModel(new WindowsEngine()));
        model.Start();
    }

    public void Stop() => model.Stop();

    public void UseSampleData()
    {
        Use(new DisplayModel(null, new DisplayState { Mode = BrightnessMode.Sync }));
        var laptop = new Display("builtin", "Built-in Display", true, ControlMethod.Native, 2880, 1800);
        var dell = new Display("dell", "DELL U2723QE", false, ControlMethod.Ddc, 3840, 2160) { HasDdc = true };
        var tv = new Display("tv", "LG TV", false, ControlMethod.Software, 1920, 1080);
        model.Simulate(new[] { laptop, dell, tv }, new Dictionary<string, DisplaySettings>
        {
            ["builtin"] = new() { Brightness = 0.55 },
            ["dell"] = new() { Brightness = 0.3, Minimum = 0.2, Maximum = 0.9, Volume = 0.4, SyncOffset = 0.1 },
            ["tv"] = new() { Brightness = 0.8, Syncs = false },
        });
    }

    private void Use(DisplayModel next)
    {
        model.Changed -= OnChanged;
        model = next;
        model.Changed += OnChanged;
        OnChanged();
    }

    private void OnChanged() => Changed?.Invoke();

    public void Open(string? display)
    {
        OpenDisplay = display;
        Changed?.Invoke();
    }

    public IReadOnlyList<ModuleTab> Tabs => new[]
    {
        new ModuleTab(Localizer.L("General"), "\uE713", () => DisplayPages.General(this)),
        new ModuleTab(Localizer.L("Displays"), "\uE7F4", () => DisplayPages.Displays(this)),
    };

    public FrameworkElement CreateMenu() => DisplayPages.Menu(this);
}
