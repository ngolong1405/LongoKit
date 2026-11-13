using System.Windows;
using System.Windows.Controls;
using LongoDisplay.Model;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoDisplay.UI;

/// <summary>Longo Display's pages and menu, laid out as in the Mac app.</summary>
internal static class DisplayPages
{
    private static LiveView Live(DisplayModule module, Func<FrameworkElement> build) =>
        new(build, refresh => module.Changed += refresh, refresh => module.Changed -= refresh);

    // MARK: - General

    public static FrameworkElement General(DisplayModule module) => Live(module, () =>
    {
        var model = module.Model;
        var power = Ui.Card(Ui.Setting(model.IsEnabled ? L("{0} is on", module.Title) : L("{0} is off", module.Title),
            model.IsEnabled ? L("Brightness, Sync and dimming are working.") : L("Off: displays keep their brightness; Sync and dimming stop."),
            Ui.Switch(model.IsEnabled, on => model.IsEnabled = on), "\uE7E8"));
        var mode = Ui.Card(Ui.Setting(L("Brightness Mode"), ModeHelp(model), ModePicker(model), "\uE706"));
        return Ui.Column(16, Ui.Section(L("Status")), power, Ui.Section(L("Brightness")), mode);
    });

    private static string ModeHelp(DisplayModel model)
    {
        if (model.Mode == BrightnessMode.Manual) return L("Each display keeps the brightness you set.");
        return model.Builtin == null
            ? L("No laptop screen now (closed, or none): external displays follow the time of day, brighter by day and dimmer in the evening.")
            : L("External displays follow the laptop screen, each within its own Sync range (set on its page), gliding to each change.");
    }

    private static Border ModePicker(DisplayModel model) =>
        Ui.Segmented(new[] { (BrightnessMode.Manual, L("Manual")), (BrightnessMode.Sync, L("Sync")) }, model.Mode, mode => model.Mode = mode);

    // MARK: - Displays

    public static FrameworkElement Displays(DisplayModule module) => Live(module, () =>
    {
        var model = module.Model;
        if (module.OpenDisplay is { } key && model.Displays.FirstOrDefault(d => d.Key == key) is { } open) return DisplayPage(module, open);
        var title = Ui.Text(L("CONNECTED DISPLAYS ({0})", model.Displays.Count), 11, FontWeights.SemiBold, "TextMuted", "MonoFont");
        var list = Ui.Column(0);
        foreach (var display in model.Displays)
        {
            if (list.Children.Count > 0) list.Children.Add(Ui.Hairline().Margin(0, 12, 0, 12));
            list.Children.Add(DisplayRow(module, display));
        }
        if (model.Displays.Count == 0) list.Children.Add(Ui.Text(L("No displays found."), 12, color: "TextMuted"));
        return Ui.Column(14, Ui.Spread(title, ModePicker(model)), AllDisplays(model), Ui.Card(list));
    });

    /// <summary>One brightness for every display, and presets.</summary>
    private static Border AllDisplays(DisplayModel model)
    {
        var lead = model.Builtin ?? model.Displays.FirstOrDefault();
        var level = lead == null ? 0.5 : model.Settings(lead).Level;
        var presets = Ui.Row(6);
        foreach (var preset in new[] { 0, 0.25, 0.5, 0.75, 1 })
            presets.Children.Add(Ui.Ghost(Ui.Percent(preset), () => model.ApplyPreset(preset)));
        var help = model.Mode == BrightnessMode.Sync
            ? L("One brightness for every display: the laptop leads and the others follow it, each within its Sync range.")
            : L("One brightness for every display.");
        var header = Ui.Row(12, Ui.Glyph("\uE8A9", 18, "VioletLight"),
                            Ui.Column(2, Ui.Row(8, Ui.Text(L("All displays"), 14, FontWeights.SemiBold), Ui.Chip(model.Mode == BrightnessMode.Sync ? L("Sync") : L("Manual"), "VioletLight", dot: true)),
                                      Ui.Text(help, 11.5, color: "TextMuted", wrap: true)));
        var slider = LevelRow(level, value => model.ApplyPreset(value), -DisplaySettings.MaxDim);
        var card = Ui.Card(Ui.Column(14, header, Ui.Spread(slider, presets.Margin(16, 0, 0, 0))));
        card.Res(Border.BorderBrushProperty, "Violet");
        return card;
    }

    private static FrameworkElement DisplayRow(DisplayModule module, Display display)
    {
        var model = module.Model;
        var heading = Ui.Row(12, Ui.Glyph(display.IsBuiltin ? "\uE7F8" : "\uE7F4", 20, "VioletLight"),
            Ui.Column(2, Ui.Row(8, Ui.Text(DisplayName(display), 14, FontWeights.SemiBold), Chips(display)),
                         Ui.Text(Subtitle(display), 11.5, color: "TextMuted")));
        var customize = Ui.Ghost(L("Customize"), () => module.Open(display.Key), "\uE76C");
        return Ui.Column(12, Ui.Spread(heading, customize), Levels(model, display));
    }

    /// <summary>A display's everyday levels: brightness (and dimming below 0%), and its speakers over DDC.</summary>
    private static FrameworkElement Levels(DisplayModel model, Display display)
    {
        var settings = model.Settings(display);
        var following = model.FollowsSync(display);
        var (lowest, _) = model.LevelRange(display);
        var brightness = LevelRow(settings.Level, value => model.SetLevel(display, value), lowest,
            following ? "\uE71B" : settings.Level < 0 ? "\uE708" : "\uE706",
            following ? L("Follows the laptop in Sync; move it to keep this display brighter or darker than that") : L("Brightness"));
        if (display.Method != ControlMethod.Ddc || settings.Volume is not { } volume) return brightness;
        var speakers = LevelRow(volume, value => model.SetVolume(display, value), 0, "\uE767", L("Speaker volume"));
        return Ui.Column(8, brightness, speakers);
    }

    /// <summary>A glyph, a slider and its value, as one row.</summary>
    private static Grid LevelRow(double value, Action<double> changed, double lowest, string glyph = "\uE706", string? tip = null)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(48) });
        var icon = Ui.Glyph(glyph, 14, value < 0 ? "VioletLight" : "Solar").Margin(0, 0, 10, 0);
        var label = Ui.Text(Ui.Percent(value), 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont");
        label.HorizontalAlignment = HorizontalAlignment.Right;
        var slider = Ui.Level(value, v =>
        {
            label.Text = Ui.Percent(v);
            changed(v);
        }, lowest, 1, tip);
        Grid.SetColumn(slider, 1);
        Grid.SetColumn(label, 2);
        grid.Children.Add(icon);
        grid.Children.Add(slider);
        grid.Children.Add(label);
        return grid;
    }

    private static Stack Chips(Display display) => Ui.Row(6,
        display.IsBuiltin ? Ui.Chip(L("Built-in"), "Emerald") : null,
        display.Method == ControlMethod.Ddc ? Ui.Chip("DDC/CI", "VioletLight", dot: true) : null,
        display.Method == ControlMethod.Software ? Ui.Chip(L("Software"), "Amber") : null);

    private static string DisplayName(Display display) => display.IsBuiltin ? L("Laptop Screen") : display.Name;

    private static string Subtitle(Display display) => $"{display.Width} × {display.Height} · " + display.Method switch
    {
        ControlMethod.Native => L("Brightness by Windows"),
        ControlMethod.Ddc => L("Hardware brightness over the cable"),
        _ => L("Dimmed in software"),
    };

    // MARK: - A display's page

    private static FrameworkElement DisplayPage(DisplayModule module, Display display)
    {
        var model = module.Model;
        var back = Ui.Ghost(L("Displays"), () => module.Open(null), "\uE72B");
        back.HorizontalAlignment = HorizontalAlignment.Left;
        var header = Ui.Card(Ui.Row(14, Ui.Glyph(display.IsBuiltin ? "\uE7F8" : "\uE7F4", 28, "VioletLight"),
            Ui.Column(4, Ui.Text(DisplayName(display), 20, FontWeights.SemiBold, font: "DisplayFont"),
                         Ui.Row(6, Chips(display), Ui.Chip($"{display.Width} × {display.Height}")))));
        var levels = Ui.Card(Levels(model, display), padding: 20);
        var page = Ui.Column(14, back, header, levels);
        if (display.HasDdc) page.Children.Add(ControlCard(model, display));
        if (display.IsBuiltin) page.Children.Add(LeadsCard(module));
        else page.Children.Add(SyncCard(model, display));
        var reset = Ui.Ghost(L("Reset This Display"), () => model.ResetDisplay(display), "\uE72C");
        reset.HorizontalAlignment = HorizontalAlignment.Right;
        page.Children.Add(reset);
        return page;
    }

    /// <summary>Hardware (DDC) or software dimming, for monitors that have DDC.</summary>
    private static Border ControlCard(DisplayModel model, Display display)
    {
        var settings = model.Settings(display);
        var picker = Ui.Segmented(new[] { (ControlChoice.Hardware, L("Hardware (DDC)")), (ControlChoice.Software, L("Software")) },
                                  settings.Control, choice => model.SetControl(display, choice));
        return Ui.Card(Ui.Setting(L("How brightness is changed"),
            L("Hardware changes the monitor's own backlight; software darkens the picture. If moving the slider doesn't change the monitor, choose Software."),
            picker, "\uE9E9"));
    }

    /// <summary>Sync for an external display: its range, a live example, the person's adjustment.</summary>
    private static Border SyncCard(DisplayModel model, Display display)
    {
        var settings = model.Settings(display);
        var syncing = model.FollowsSync(display);
        var header = Ui.Setting(L("Sync with the laptop"),
            L("This display follows the laptop screen's brightness, moving within this range. The laptop itself doesn't change."),
            Ui.Switch(syncing, on => model.SetSyncs(display, on)), "\uE71B");
        var lowest = Ui.Setting(L("Lowest"), null, Range(settings.Minimum, value => model.SetSyncRange(display, value, model.Settings(display).Maximum)));
        var highest = Ui.Setting(L("Highest"), null, Range(settings.Maximum, value => model.SetSyncRange(display, model.Settings(display).Minimum, value)));
        var source = model.Builtin != null ? L("Laptop") : L("Time of day");
        var example = Ui.Row(8, Ui.Glyph(model.Builtin != null ? "\uE7F8" : "\uE706", 12, "TextMuted"),
                             Ui.Text($"{source} {Ui.Percent(model.SyncSource)}", 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont"),
                             Ui.Glyph("\uE72A", 10, "TextFaint"),
                             Ui.Text($"{DisplayName(display)} {Ui.Percent(model.SyncTarget(display))}", 11.5, FontWeights.SemiBold, "Solar", "MonoFont"));
        var column = Ui.Column(14, header, Ui.Hairline(), lowest, highest, example);
        if (Math.Abs(settings.SyncOffset) >= 0.005)
        {
            var amount = (settings.SyncOffset > 0 ? "+" : "−") + Ui.Percent(Math.Abs(settings.SyncOffset));
            column.Children.Add(Ui.Spread(Ui.Row(8, Ui.Glyph("\uE9E9", 12, "VioletLight"), Ui.Text(L("Your adjustment: {0}", amount), 12, FontWeights.Medium, "TextSecondary")),
                                          Ui.Ghost(L("Reset"), () => model.ResetSyncOffset(display)).Tip(L("Follow the range again, without the adjustment"))));
        }
        column.Children.Add(Ui.Text(L("Laptop at 0% puts this display at the lowest; at 100%, at the highest, matching how bright the two look. Move its brightness to keep it brighter or darker. With the laptop closed, it follows the time of day."),
                                    11, color: "TextFaint", wrap: true));
        return Ui.Card(column);
    }

    private static FrameworkElement Range(double value, Action<double> changed)
    {
        var label = Ui.Text(Ui.Percent(value), 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont");
        var slider = Ui.Level(value, v =>
        {
            label.Text = Ui.Percent(v);
            changed(v);
        });
        slider.Width = 220;
        return Ui.Row(10, slider, label);
    }

    /// <summary>The laptop screen leads Sync: every external display, its range, and where it is now.</summary>
    private static Border LeadsCard(DisplayModule module)
    {
        var model = module.Model;
        var column = Ui.Column(12, Ui.Setting(L("Leads Sync"), L("In Sync, external displays follow this screen's brightness, each within its own range."),
            model.Mode == BrightnessMode.Sync ? Ui.Chip(L("On"), "Emerald", dot: true) : Ui.Ghost(L("Use Sync"), () => model.Mode = BrightnessMode.Sync), "\uE71B"));
        foreach (var display in model.Externals)
        {
            var settings = model.Settings(display);
            column.Children.Add(Ui.Spread(Ui.Row(8, Ui.Glyph("\uE7F4", 13, "VioletLight"), Ui.Text(display.Name, 12, FontWeights.Medium)),
                Ui.Row(8, Ui.Text($"{Ui.Percent(settings.Minimum)}–{Ui.Percent(settings.Maximum)}", 11, color: "TextMuted", font: "MonoFont"),
                          Ui.Glyph("\uE72A", 10, "TextFaint"),
                          Ui.Text(Ui.Percent(model.SyncTarget(display)), 11, FontWeights.SemiBold, "Solar", "MonoFont"))));
        }
        return Ui.Card(column);
    }

    // MARK: - Menu

    public static FrameworkElement Menu(DisplayModule module) => Live(module, () =>
    {
        var model = module.Model;
        var column = Ui.Column(14, Ui.Spread(Ui.Text(L("Brightness Mode"), 12, FontWeights.Medium, "TextSecondary"), ModePicker(model)));
        if (model.Mode == BrightnessMode.Sync)
            column.Children.Add(Ui.Text(L("External displays follow the laptop screen. Choose Manual to set each one yourself."), 11, color: "TextMuted", wrap: true));
        foreach (var display in model.Displays)
            column.Children.Add(Ui.Column(6, Ui.Row(8, Ui.Text(DisplayName(display), 13, FontWeights.Medium), Chips(display)), Levels(model, display)));
        if (!model.IsEnabled) column.Opacity = 0.5;
        return column;
    });
}
