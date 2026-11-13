using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Threading;

namespace LongoKit.UI;

/// <summary>The app-wide settings: language and appearance (each module keeps its own in its file).</summary>
public sealed class ShellSettings
{
    public AppLanguage Language { get; set; } = AppLanguage.System;
    public Appearance Appearance { get; set; } = Appearance.System;
}

/// <summary>What the shell shows about the app it runs.</summary>
public sealed record AppInfo(string Id, string Name, string IconName, string Website, string ReleaseNotes);

/// <summary>
/// Runs one module as its own app (Longo Display), or several as LongoKit: the notification area icon and its menu,
/// the settings window, one copy at a time, starting with Windows, and `--snapshot` (the pages as pictures, for CI).
/// </summary>
public sealed class LongoShell
{
    public AppInfo Info { get; }
    public IReadOnlyList<ILongoModule> Modules { get; }
    public ShellSettings Settings { get; }
    public event Action? Changed;

    private TrayIcon? tray;
    private MenuWindow? menu;
    private SettingsWindow? window;

    public LongoShell(AppInfo info, IReadOnlyList<ILongoModule> modules)
    {
        Info = info;
        Modules = modules;
        Settings = Store.Load<ShellSettings>("shell-" + info.Id);
        Localizer.Language = Settings.Language;
    }

    public static string Version =>
        Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0.0.0";

    /// <summary>Runs the app; returns its exit code. Call from an [STAThread] Main.</summary>
    public int Run(string[] args)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        Theme.Apply(Settings.Appearance);

        var snapshot = Array.IndexOf(args, "--snapshot");
        if (snapshot >= 0 && snapshot + 1 < args.Length) return Snapshot.Render(this, args[snapshot + 1]);

        using var instance = new SingleInstance("LongoKit." + Info.Id);
        if (!instance.IsFirst)
        {
            instance.SignalFirst();
            return 0;
        }
        instance.OnSignal(() => app.Dispatcher.BeginInvoke(() => ShowWindow()));

        app.Dispatcher.UnhandledException += (_, e) =>
        {
            Trace.WriteLine(e.Exception);
            e.Handled = true;
        };
        foreach (var module in Modules)
        {
            module.Changed += () => app.Dispatcher.BeginInvoke(() => Changed?.Invoke());
            module.Start();
        }
        tray = new TrayIcon(this);
        // Opened by the person (not at sign-in): show the window, so the app is seen to have started.
        if (Array.IndexOf(args, "--background") < 0) ShowWindow();
        app.Exit += (_, _) =>
        {
            foreach (var module in Modules) module.Stop();
            tray?.Dispose();
        };
        return app.Run();
    }

    public void ShowWindow(ILongoModule? module = null)
    {
        menu?.Hide();
        window ??= new SettingsWindow(this);
        if (module != null) window.Open(module);
        window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }

    public void ToggleMenu()
    {
        menu ??= new MenuWindow(this);
        if (menu.IsVisible) menu.Hide();
        else menu.ShowNearTray();
    }

    public void Quit() => Application.Current.Shutdown();

    public void SetLanguage(AppLanguage language)
    {
        Settings.Language = language;
        Localizer.Language = language;
        Save();
    }

    public void SetAppearance(Appearance appearance)
    {
        Settings.Appearance = appearance;
        Theme.Apply(appearance);
        Save();
    }

    private void Save()
    {
        Store.Save("shell-" + Info.Id, Settings);
        Changed?.Invoke();
    }

    /// <summary>Whether the window or the menu is on screen (a module may only need to watch things then).</summary>
    public bool IsShowing => window?.IsVisible == true || menu?.IsVisible == true;

    internal static void OpenLink(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}

/// <summary>One copy of the app at a time: a second one tells the first to show its window, then quits.</summary>
internal sealed class SingleInstance : IDisposable
{
    private readonly Mutex mutex;
    private readonly EventWaitHandle signal;
    private RegisteredWaitHandle? waiting;

    public bool IsFirst { get; }

    public SingleInstance(string name)
    {
        mutex = new Mutex(true, @"Local\" + name, out var created);
        IsFirst = created;
        signal = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\" + name + ".show");
    }

    public void SignalFirst() => signal.Set();

    public void OnSignal(Action action) =>
        waiting = ThreadPool.RegisterWaitForSingleObject(signal, (_, _) => action(), null, Timeout.Infinite, executeOnlyOnce: false);

    public void Dispose()
    {
        waiting?.Unregister(null);
        signal.Dispose();
        if (IsFirst) mutex.ReleaseMutex();
        mutex.Dispose();
    }
}
