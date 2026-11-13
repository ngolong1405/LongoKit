using System.Windows;
using System.Windows.Controls;

namespace LongoKit.UI;

/// <summary>The pages every app has: the app settings (language, appearance, starting with Windows) and About.</summary>
public static class Pages
{
    public static Border AppCard(LongoShell shell)
    {
        var language = Ui.Segmented(new[]
        {
            (AppLanguage.System, Localizer.L("System")), (AppLanguage.English, "English"), (AppLanguage.Vietnamese, "Tiếng Việt"),
        }, shell.Settings.Language, shell.SetLanguage);
        var appearance = Ui.Segmented(new[]
        {
            (Appearance.System, Localizer.L("System")), (Appearance.Dark, Localizer.L("Dark")), (Appearance.Light, Localizer.L("Light")),
        }, shell.Settings.Appearance, shell.SetAppearance);
        var login = Ui.Switch(StartWithWindows.IsOn(shell.Info.Name), on => StartWithWindows.Set(shell.Info.Name, on));
        return Ui.Card(Ui.Column(14,
            Ui.Setting(Localizer.L("Language"), null, language, "\uE774"),
            Ui.Hairline(),
            Ui.Setting(Localizer.L("Appearance"), null, appearance, "\uE793"),
            Ui.Hairline(),
            Ui.Setting(Localizer.L("Start with Windows"), Localizer.L("Opens in the notification area when you sign in."), login, "\uE7E8")));
    }

    /// <summary>LongoKit's own page: each module with its switch, then the app settings.</summary>
    public static FrameworkElement KitGeneral(LongoShell shell)
    {
        var modules = Ui.Column(0);
        foreach (var module in shell.Modules)
        {
            if (modules.Children.Count > 0) modules.Children.Add(Ui.Hairline().Margin(0, 12, 0, 12));
            var logo = new Image { Source = Icons.App(module.IconName, 64), Width = 34, Height = 34 };
            var text = Ui.Column(2, Ui.Text(module.Title, 14, FontWeights.SemiBold), Ui.Text(Localizer.L(module.Blurb), 11.5, color: "TextMuted"));
            var each = module;
            var toggle = new LiveView(() => Ui.Switch(each.IsOn, on => each.SetOn(on),
                                                      each.IsOn ? Localizer.L("Turn {0} off", each.Title) : Localizer.L("Turn {0} on", each.Title)),
                                      refresh => each.Changed += refresh, refresh => each.Changed -= refresh);
            var open = Ui.Ghost(Localizer.L("Open"), () => shell.ShowWindow(each), "\uE76C");
            modules.Children.Add(Ui.Spread(Ui.Row(12, logo, text), Ui.Row(12, open, toggle)));
        }
        return Ui.Column(16,
            Ui.Section(Localizer.L("Modules")),
            Ui.Card(modules),
            Ui.Text(Localizer.L("A module that's off stops at once and leaves your settings as they are."), 11.5, color: "TextFaint", wrap: true).Margin(2, 0, 0, 0),
            Ui.Section(Localizer.L("App")),
            AppCard(shell));
    }

    public static FrameworkElement About(LongoShell shell, ILongoModule? module)
    {
        var logo = new Image { Source = Icons.App(shell.Info.IconName, 128), Width = 88, Height = 88, HorizontalAlignment = HorizontalAlignment.Center };
        var name = Ui.Text(shell.Info.Name, 24, FontWeights.SemiBold, font: "DisplayFont");
        name.HorizontalAlignment = HorizontalAlignment.Center;
        var version = Ui.Text(Localizer.L("Version {0}", LongoShell.Version) + " · beta", 12, color: "TextMuted", font: "MonoFont");
        version.HorizontalAlignment = HorizontalAlignment.Center;
        var blurb = Ui.Text(!shell.IsSuite && module != null ? Localizer.L(module.Blurb) : Localizer.L("Mouse, Display & Shot in one app"), 13, color: "TextSecondary", wrap: true);
        blurb.HorizontalAlignment = HorizontalAlignment.Center;
        blurb.TextAlignment = TextAlignment.Center;
        var links = Ui.Row(8,
            Ui.Ghost(Localizer.L("Website"), () => LongoShell.OpenLink(shell.Info.Website), "\uE774"),
            Ui.Ghost(Localizer.L("Release notes"), () => LongoShell.OpenLink(shell.Info.ReleaseNotes), "\uE8A5"),
            Ui.Ghost("GitHub", () => LongoShell.OpenLink("https://github.com/ngolong1405/LongoKit"), "\uE943"));
        links.HorizontalAlignment = HorizontalAlignment.Center;
        var note = Ui.Text(Localizer.L("Beta. Not signed yet: Windows may warn before the first launch (More info › Run anyway).") + "\n" +
                           Localizer.L("Made by Long Ngô."), 11.5, color: "TextFaint", wrap: true);
        note.TextAlignment = TextAlignment.Center;
        return Ui.Card(Ui.Column(12, logo, name, version, blurb, links, note).Margin(0, 12, 0, 12), padding: 28);
    }
}

/// <summary>Starting with Windows: the app's entry under the signed-in person's Run key, opening in the background.</summary>
public static class StartWithWindows
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsOn(string name)
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue(name) is string;
    }

    public static void Set(string name, bool on)
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey);
        if (on) key.SetValue(name, $"\"{Environment.ProcessPath}\" --background");
        else key.DeleteValue(name, throwOnMissingValue: false);
    }
}
