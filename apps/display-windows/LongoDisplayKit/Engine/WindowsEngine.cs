using System.Management;
using System.Windows.Threading;
using LongoDisplay.Model;
using Microsoft.Win32;

namespace LongoDisplay.Engine;

/// <summary>
/// The displays as Windows has them: a laptop screen's brightness through WMI (as its keys and adaptive brightness
/// change it), monitors' brightness and volume over DDC/CI (dxva2), and dimming as a click-through layer over a screen.
/// </summary>
public sealed class WindowsEngine : IDisplayEngine
{
    private readonly Dispatcher dispatcher = Dispatcher.CurrentDispatcher;
    private readonly Dictionary<string, IntPtr> physical = new();
    private readonly Dictionary<string, Coalescer<double>> brightnessWrites = new();
    private readonly Dictionary<string, Coalescer<double>> volumeWrites = new();
    private readonly Dimmer dimmer = new();
    private readonly Coalescer<double> laptopWrites;
    private ManagementEventWatcher? watcher;
    private double? builtin;

    public event Action? BuiltinChanged;
    public event Action? DisplaysChanged;

    public WindowsEngine()
    {
        laptopWrites = new Coalescer<double>(value => Laptop.Set(value));
        builtin = Laptop.Read();
        // Windows tells when the laptop screen's brightness changes; reading it on every check would be slow.
        try
        {
            watcher = new ManagementEventWatcher(new ManagementScope(@"root\WMI"), new EventQuery("SELECT * FROM WmiMonitorBrightnessEvent"));
            watcher.EventArrived += (_, e) =>
            {
                if (e.NewEvent["Brightness"] is byte value) Update(value / 100.0);
            };
            watcher.Start();
        }
        catch (Exception error) when (error is ManagementException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
        {
            watcher = null;
        }
        SystemEvents.DisplaySettingsChanged += OnDisplaysChanged;
    }

    private void OnDisplaysChanged(object? sender, EventArgs e) => dispatcher.BeginInvoke(() => DisplaysChanged?.Invoke());

    private void Update(double value) => dispatcher.BeginInvoke(() =>
    {
        if (builtin is { } old && Math.Abs(old - value) < 0.001) return;
        builtin = value;
        BuiltinChanged?.Invoke();
    });

    public double? BuiltinBrightness => builtin;

    public IReadOnlyList<Display> List()
    {
        foreach (var handle in physical.Values) Native.DestroyPhysicalMonitor(handle);
        physical.Clear();
        var names = Wmi.MonitorNames();
        var internals = Wmi.InternalMonitors();
        var displays = new List<Display>();
        foreach (var monitor in Monitors())
        {
            var info = new Native.MonitorInfoEx { Size = System.Runtime.InteropServices.Marshal.SizeOf<Native.MonitorInfoEx>() };
            if (!Native.GetMonitorInfo(monitor, ref info)) continue;
            var device = new Native.DisplayDevice { Size = System.Runtime.InteropServices.Marshal.SizeOf<Native.DisplayDevice>() };
            var key = Native.EnumDisplayDevices(info.Device, 0, ref device, Native.GetDeviceInterfaceName) && !string.IsNullOrEmpty(device.DeviceId)
                ? device.DeviceId.ToLowerInvariant()
                : info.Device.ToLowerInvariant();
            var instance = Wmi.InstanceName(key);
            var isBuiltin = instance != null && internals.Contains(instance);
            var name = instance != null && names.TryGetValue(instance, out var friendly) ? friendly : device.DeviceString;
            var handle = PhysicalMonitor(monitor);
            var hasDdc = handle != IntPtr.Zero && Native.GetVCPFeatureAndVCPFeatureReply(handle, 0x10, out _, out _, out var maximum) && maximum > 0;
            if (handle != IntPtr.Zero) physical[key] = handle;
            var method = isBuiltin && builtin != null ? ControlMethod.Native : hasDdc ? ControlMethod.Ddc : ControlMethod.Software;
            displays.Add(new Display(key, string.IsNullOrWhiteSpace(name) ? "Display" : name, isBuiltin, method,
                                           info.Monitor.Width, info.Monitor.Height)
            {
                HasDdc = hasDdc,
                Left = info.Monitor.Left,
                Top = info.Monitor.Top,
            });
        }
        return displays;
    }

    private static List<IntPtr> Monitors()
    {
        var monitors = new List<IntPtr>();
        Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr monitor, IntPtr _, ref Native.Rect _, IntPtr _) =>
        {
            monitors.Add(monitor);
            return true;
        }, IntPtr.Zero);
        return monitors;
    }

    private static IntPtr PhysicalMonitor(IntPtr monitor)
    {
        if (!Native.GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out var count) || count == 0) return IntPtr.Zero;
        var monitors = new Native.PhysicalMonitor[count];
        if (!Native.GetPhysicalMonitorsFromHMONITOR(monitor, count, monitors)) return IntPtr.Zero;
        for (var index = 1; index < monitors.Length; index++) Native.DestroyPhysicalMonitor(monitors[index].Handle);
        return monitors[0].Handle;
    }

    public Task<double?> ReadBrightness(Display display) => Read(display, 0x10);

    public Task<double?> ReadVolume(Display display) => Read(display, 0x62);

    private Task<double?> Read(Display display, byte code)
    {
        if (!physical.TryGetValue(display.Key, out var handle)) return Task.FromResult<double?>(null);
        return Task.Run<double?>(() =>
            Native.GetVCPFeatureAndVCPFeatureReply(handle, code, out _, out var current, out var maximum) && maximum > 0
                ? (double)current / maximum
                : null);
    }

    public void Apply(Display display, DisplaySettings settings)
    {
        var hardware = display.Method switch
        {
            ControlMethod.Native => true,
            ControlMethod.Ddc => settings.Control == ControlChoice.Hardware,
            _ => false,
        };
        if (hardware && display.Method == ControlMethod.Native) laptopWrites.Submit(settings.Brightness);
        else if (hardware) Writer(brightnessWrites, display, 0x10).Submit(settings.Brightness);
        // Below 0% the picture is dimmed further; done in software, the whole range is dimming.
        var dim = hardware ? settings.ExtraDim : (1 - settings.Brightness) * 0.85;
        dimmer.Set(display, dim);
    }

    public void SetVolume(Display display, double volume) => Writer(volumeWrites, display, 0x62).Submit(volume);

    private Coalescer<double> Writer(Dictionary<string, Coalescer<double>> writers, Display display, byte code)
    {
        if (writers.TryGetValue(display.Key, out var writer)) return writer;
        var key = display.Key;
        writer = new Coalescer<double>(value =>
        {
            if (!physical.TryGetValue(key, out var handle)) return;
            if (!Native.GetVCPFeatureAndVCPFeatureReply(handle, code, out _, out _, out var maximum) || maximum == 0) maximum = 100;
            Native.SetVCPFeature(handle, code, (uint)Math.Round(Math.Clamp(value, 0, 1) * maximum));
        });
        writers[display.Key] = writer;
        return writer;
    }

    public void ClearDimming() => dimmer.Clear();

    public void Dispose()
    {
        SystemEvents.DisplaySettingsChanged -= OnDisplaysChanged;
        watcher?.Stop();
        watcher?.Dispose();
        dimmer.Clear();
        foreach (var handle in physical.Values) Native.DestroyPhysicalMonitor(handle);
        physical.Clear();
    }
}

/// <summary>The laptop screen's brightness through WMI.</summary>
internal static class Laptop
{
    public static double? Read()
    {
        try
        {
            foreach (var item in Wmi.Query("WmiMonitorBrightness"))
                if (item["CurrentBrightness"] is byte value) return value / 100.0;
        }
        catch (Exception error) when (error is ManagementException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException) { }
        return null;
    }

    public static void Set(double value)
    {
        foreach (var item in Wmi.Query("WmiMonitorBrightnessMethods"))
            item.InvokeMethod("WmiSetBrightness", new object[] { (uint)1, (byte)Math.Round(Math.Clamp(value, 0, 1) * 100) });
    }
}

/// <summary>Monitors' names and connections, from WMI (root\WMI).</summary>
internal static class Wmi
{
    public static IEnumerable<ManagementObject> Query(string type)
    {
        using var searcher = new ManagementObjectSearcher(@"root\WMI", $"SELECT * FROM {type}");
        foreach (var item in searcher.Get()) yield return (ManagementObject)item;
    }

    /// <summary>"\\?\display#gsm5b7f#5&amp;2ba4a9d&amp;0&amp;uid4353#{...}" → "display\gsm5b7f\5&amp;2ba4a9d&amp;0&amp;uid4353_0", as WMI names it.</summary>
    public static string? InstanceName(string devicePath)
    {
        var parts = devicePath.TrimStart('\\', '?').Split('#');
        return parts.Length >= 3 ? $@"{parts[0]}\{parts[1]}\{parts[2]}_0".ToLowerInvariant() : null;
    }

    /// <summary>Each monitor's own name ("DELL U2723QE"), by its WMI instance name.</summary>
    public static Dictionary<string, string> MonitorNames()
    {
        var names = new Dictionary<string, string>();
        try
        {
            foreach (var item in Query("WmiMonitorID"))
            {
                if (item["InstanceName"] is not string instance || item["UserFriendlyName"] is not ushort[] chars) continue;
                var name = new string(chars.TakeWhile(c => c != 0).Select(c => (char)c).ToArray()).Trim();
                if (name.Length > 0) names[instance.ToLowerInvariant()] = name;
            }
        }
        catch (Exception error) when (error is ManagementException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException) { }
        return names;
    }

    /// <summary>The monitors built into the computer (a laptop's screen), by WMI instance name.</summary>
    public static HashSet<string> InternalMonitors()
    {
        var internals = new HashSet<string>();
        try
        {
            foreach (var item in Query("WmiMonitorConnectionParams"))
            {
                if (item["InstanceName"] is not string instance) continue;
                // Internal, DisplayPort embedded, UDI embedded.
                var technology = Convert.ToInt64(item["VideoOutputTechnology"]) & 0xFFFFFFFF;
                if (technology is 0x80000000 or 11 or 13) internals.Add(instance.ToLowerInvariant());
            }
        }
        catch (Exception error) when (error is ManagementException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException) { }
        return internals;
    }
}
