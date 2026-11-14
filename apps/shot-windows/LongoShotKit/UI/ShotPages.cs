using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using LongoKit.UI;
using LongoShot.Engine;
using LongoShot.Model;
using static LongoKit.UI.Localizer;

namespace LongoShot.UI;

/// <summary>Longo Shot's pages and menu, laid out as in the Mac app.</summary>
internal static class ShotPages
{
    private static LiveView Live(ShotModule module, Func<FrameworkElement> build) =>
        new(build, refresh => module.Changed += refresh, refresh => module.Changed -= refresh);

    public static string Title(ShotAction action) => action switch
    {
        ShotAction.CaptureArea => L("Capture Area or Window"),
        ShotAction.CaptureScreen => L("Capture Full Screen"),
        _ => L("Copy Text (OCR)"),
    };

    private static string Glyph(ShotAction action) => action switch
    {
        ShotAction.CaptureArea => "\uF407",
        ShotAction.CaptureScreen => "\uE740",
        _ => "\uE8C1",
    };

    public static FrameworkElement General(ShotModule module) => Live(module, () =>
    {
        var model = module.Model;
        var state = model.State;
        var power = Ui.Card(Ui.Setting(state.IsEnabled ? L("{0} is on", module.Title) : L("{0} is off", module.Title),
            state.IsEnabled ? L("Its shortcuts work in every app.") : L("Off: its shortcuts let go, so other apps can use them; the menu still captures."),
            Ui.Switch(state.IsEnabled, module.SetOn), "\uE7E8"));
        var folder = Ui.Spread(Ui.Text(state.Folder, 12, color: "TextSecondary", font: "MonoFont"),
            Ui.Row(6, Ui.Ghost(L("Change…"), () =>
            {
                var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = state.Folder };
                if (dialog.ShowDialog() == true) model.Change(s => s.Folder = dialog.FolderName);
            }), Ui.IconButton("\uE8DA", module.OpenFolder, L("Open the folder"))));
        var captures = Ui.Card(Ui.Column(14,
            Ui.Setting(L("Save to the folder"), L("Each capture as a PNG."), Ui.Switch(state.SaveToFolder, on => model.Change(s => s.SaveToFolder = on)), "\uE74E"),
            Ui.Well(folder, 10),
            Ui.Hairline(),
            Ui.Setting(L("Copy to the clipboard"), null, Ui.Switch(state.CopyToClipboard, on => model.Change(s => s.CopyToClipboard = on)), "\uE8C8"),
            Ui.Setting(L("Draw on it"), L("The capture stays where it was, with the drawing toolbar under it."), Ui.Switch(state.DrawAfterCapture, on => model.Change(s => s.DrawAfterCapture = on)), "\uE70F"),
            Ui.Setting(L("Preview"), L("A small card in the corner; click it to open the picture."), Ui.Switch(state.ShowPreview, on => model.Change(s => s.ShowPreview = on)), "\uE8B9"),
            Ui.Setting(L("Recent"), L("The last 10 captures in the menu."), Ui.Switch(state.KeepRecent, on => model.Change(s => s.KeepRecent = on)), "\uE81C")));
        var languages = Ocr.Languages();
        var text = Ui.Card(Ui.Setting(L("Text recognition"),
            languages.Count == 0 ? L("Windows has no text recognition languages yet: add one in Settings › Time & language › Language.")
                                 : L("Read on this PC, nothing is uploaded: {0}.", string.Join(", ", languages.Select(l => l.Name))),
            null, "\uE8C1"));
        return Ui.Column(16, Ui.Section(L("Status")), power, Ui.Section(L("Captures")), captures, Ui.Section(L("Copy Text")), text);
    });

    public static FrameworkElement Shortcuts(ShotModule module) => Live(module, () =>
    {
        var rows = Ui.Column(12);
        foreach (var (action, hotkey) in ShotModule.Shortcuts)
        {
            if (rows.Children.Count > 0) rows.Children.Add(Ui.Hairline());
            var key = module.Taken.Contains(action) ? Ui.Chip(L("Taken by another app"), "Amber", dot: true) : Ui.Chip(hotkey.Name, "Solar");
            rows.Children.Add(Ui.Setting(Title(action), null, key, Glyph(action)));
        }
        rows.Children.Add(Ui.Hairline());
        rows.Children.Add(Ui.Setting(L("Record Screen"), null, Ui.Chip(L("Coming soon")), "\uE714"));
        var help = Ui.Text(L("While picking: drag an area, click a window, double-click for the whole screen. While drawing: A P R O H pick a tool, Ctrl+Z undoes, Enter or Ctrl+C saves and copies, Esc goes back to picking."),
                           11.5, color: "TextFaint", wrap: true);
        return Ui.Column(16, Ui.Card(rows), help);
    });

    public static FrameworkElement Menu(ShotModule module) => Live(module, () =>
    {
        var column = Ui.Column(6);
        foreach (var (action, hotkey) in ShotModule.Shortcuts)
        {
            var row = new Button
            {
                Content = Ui.Spread(Ui.Row(10, Ui.Glyph(Glyph(action), 15, "Solar"), Ui.Text(Title(action), 13, FontWeights.Medium)), Ui.Chip(hotkey.Name)),
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Padding = new Thickness(10, 0, 10, 0),
                Height = 38,
                Width = 346,
            };
            row.SetResourceReference(FrameworkElement.StyleProperty, "LongoIconButton");
            row.Click += (_, _) => module.Run(action, fromMenu: true);
            column.Children.Add(row);
        }
        var recent = module.Model.RecentCaptures;
        if (recent.Count > 0)
        {
            column.Children.Add(Ui.Hairline().Margin(0, 6, 0, 6));
            column.Children.Add(Ui.Spread(Ui.Text(L("Recent"), 12, FontWeights.SemiBold, "TextSecondary"), Ui.IconButton("\uE8DA", module.OpenFolder, L("Open the folder"))));
            var grid = new WrapPanel();
            foreach (var capture in recent.Take(6))
            {
                var image = new Image { Source = ShotModel.Thumbnail(capture.File), Width = 108, Height = 66, Stretch = System.Windows.Media.Stretch.UniformToFill };
                var tile = new Border { Child = image, CornerRadius = new CornerRadius(7), ClipToBounds = true, Margin = new Thickness(0, 0, 6, 6), Cursor = Cursors.Hand }
                    .Tip(L("Click: copy · Double-click: open"));
                tile.MouseLeftButtonUp += (_, e) =>
                {
                    if (e.ClickCount >= 2) Process.Start(new ProcessStartInfo(capture.File) { UseShellExecute = true });
                    else if (ShotModel.Thumbnail(capture.File, 4096) is { } full) Output.Copy(full);
                };
                grid.Children.Add(tile);
            }
            column.Children.Add(grid);
        }
        if (!module.IsOn) column.Children.Add(Ui.Text(L("Off: the shortcuts don't work; these buttons still capture."), 11, color: "TextMuted", wrap: true));
        return column;
    });
}
