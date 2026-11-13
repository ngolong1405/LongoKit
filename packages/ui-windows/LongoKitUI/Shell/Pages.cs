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

    public static FrameworkElement About(LongoShell shell, ILongoModule module)
    {
        var logo = new Image { Source = Icons.App(shell.Info.IconName, 128), Width = 88, Height = 88, HorizontalAlignment = HorizontalAlignment.Center };
        var name = Ui.Text(shell.Info.Name, 24, FontWeights.SemiBold, font: "DisplayFont");
        name.HorizontalAlignment = HorizontalAlignment.Center;
        var version = Ui.Text(Localizer.L("Version {0}", LongoShell.Version) + " · beta", 12, color: "TextMuted", font: "MonoFont");
        version.HorizontalAlignment = HorizontalAlignment.Center;
        var blurb = Ui.Text(shell.Modules.Count == 1 ? Localizer.L(module.Blurb) : Localizer.L("Mouse, Display & Shot in one app"), 13, color: "TextSecondary", wrap: true);
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
