using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Forms = System.Windows.Forms;

namespace LongoKit.UI;

/// <summary>
/// The app's icon in the notification area. Click: the menu. Double-click: the window. Right-click: a short menu
/// (Settings…, the on/off switches, About, Quit), as the Mac apps' menu bar icon does.
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly LongoShell shell;
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.Timer clickTimer = new();
    /// <summary>The right-click menu needs a window of the app's to be active, or it doesn't close on its own.</summary>
    private Window? anchor;

    public TrayIcon(LongoShell shell)
    {
        this.shell = shell;
        var stream = Application.GetResourceStream(new Uri($"pack://application:,,,/LongoKitUI;component/Icons/{shell.Info.IconName}"))!.Stream;
        icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            Text = shell.Info.Name,
            Visible = true,
        };
        // A double-click is told from a click by waiting the double-click time first.
        clickTimer.Interval = Forms.SystemInformation.DoubleClickTime;
        clickTimer.Tick += (_, _) =>
        {
            clickTimer.Stop();
            shell.ToggleMenu();
        };
        icon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) clickTimer.Start();
            else if (e.Button == Forms.MouseButtons.Right) ShowShortMenu();
        };
        icon.MouseDoubleClick += (_, e) =>
        {
            if (e.Button != Forms.MouseButtons.Left) return;
            clickTimer.Stop();
            shell.ShowWindow();
        };
    }

    private void ShowShortMenu()
    {
        var menu = new ContextMenu { Placement = PlacementMode.MousePoint };
        menu.Items.Add(Item(Localizer.L("Settings…"), () => shell.ShowWindow()));
        menu.Items.Add(new Separator());
        foreach (var module in shell.Modules)
        {
            var item = Item(shell.Modules.Count > 1 ? module.Title : (module.IsOn ? Localizer.L("{0} is on", module.Title) : Localizer.L("{0} is off", module.Title)),
                            () => module.SetOn(!module.IsOn));
            item.IsCheckable = true;
            item.IsChecked = module.IsOn;
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(Localizer.L("About"), () => shell.ShowWindow()));
        menu.Items.Add(Item(Localizer.L("Quit {0}", shell.Info.Name), shell.Quit));

        anchor ??= new Window
        {
            Width = 1, Height = 1, WindowStyle = WindowStyle.None, ShowInTaskbar = false, Opacity = 0,
            AllowsTransparency = true, Topmost = true, Left = -10000, Top = -10000,
        };
        anchor.Show();
        anchor.Activate();
        menu.PlacementTarget = anchor;
        menu.Closed += (_, _) => anchor.Hide();
        menu.IsOpen = true;
    }

    private static MenuItem Item(string title, Action action)
    {
        var item = new MenuItem { Header = title };
        item.Click += (_, _) => action();
        return item;
    }

    public void Dispose()
    {
        clickTimer.Dispose();
        icon.Visible = false;
        icon.Dispose();
        anchor?.Close();
    }
}
