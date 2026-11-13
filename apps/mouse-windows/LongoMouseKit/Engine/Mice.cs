using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Interop;
using static LongoMouse.Engine.Native;

namespace LongoMouse.Engine;

/// <summary>A mouse connected now. <see cref="Key"/> ("046D:B034") keeps its settings across reconnects.</summary>
public sealed record MouseDevice(string Key, string Product, string Manufacturer, string Connection);

/// <summary>
/// The mice, through Raw Input: which are connected (by name, from HID), and which one moved last, so its own settings
/// can follow it. Touchpads and Remote Desktop's virtual mouse are left out.
/// </summary>
public sealed partial class Mice : IDisposable
{
    private readonly HwndSource window;
    private readonly Dictionary<IntPtr, string> keys = new();

    public IReadOnlyList<MouseDevice> Connected { get; private set; } = Array.Empty<MouseDevice>();
    /// <summary>The mouse that moved last.</summary>
    public string? InUse { get; private set; }
    /// <summary>The mice connected changed, or another one was used.</summary>
    public event Action? Changed;

    public Mice()
    {
        // A message-only window, for Raw Input's messages.
        window = new HwndSource(new HwndSourceParameters("Longo Mouse input") { ParentWindow = new IntPtr(-3), WindowStyle = 0 });
        window.AddHook(Message);
        var device = new RawInputDevice { UsagePage = 1, Usage = 2, Flags = RawInputSink | RawDeviceNotify, Target = window.Handle };
        RegisterRawInputDevices(new[] { device }, 1, (uint)Marshal.SizeOf<RawInputDevice>());
        Refresh();
    }

    public void Refresh()
    {
        keys.Clear();
        var found = new Dictionary<string, MouseDevice>();
        uint count = 0;
        var size = (uint)Marshal.SizeOf<RawInputDeviceListItem>();
        GetRawInputDeviceList(null, ref count, size);
        var list = new RawInputDeviceListItem[count];
        if (count > 0) GetRawInputDeviceList(list, ref count, size);
        foreach (var item in list.Where(i => i.Type == TypeMouse))
        {
            var path = DevicePath(item.Device);
            if (path == null || path.StartsWith(@"\\?\Root#", StringComparison.OrdinalIgnoreCase)) continue;
            var key = Key(path);
            if (key == null) continue;
            var (product, manufacturer) = HidNames(path);
            if (product.Contains("touchpad", StringComparison.OrdinalIgnoreCase) || product.Contains("trackpad", StringComparison.OrdinalIgnoreCase)) continue;
            keys[item.Device] = key;
            // A mouse can show up more than once (its HID collections): one entry each.
            if (!found.ContainsKey(key)) found[key] = new MouseDevice(key, product, manufacturer, Connection(path));
        }
        Connected = found.Values.OrderBy(m => m.Product).ToList();
        if (InUse != null && !found.ContainsKey(InUse)) InUse = null;
        if (InUse == null && Connected.Count == 1) InUse = Connected[0].Key;
        Changed?.Invoke();
    }

    private IntPtr Message(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == WmInputDeviceChange)
        {
            Refresh();
        }
        else if (message == WmInput)
        {
            var header = (uint)Marshal.SizeOf<RawInputHeader>();
            var size = header;
            var buffer = Marshal.AllocHGlobal((int)header);
            try
            {
                if (GetRawInputData(lParam, 0x10000005 /* RID_HEADER */, buffer, ref size, header) != unchecked((uint)-1))
                {
                    var device = Marshal.PtrToStructure<RawInputHeader>(buffer).Device;
                    if (keys.TryGetValue(device, out var key) && key != InUse)
                    {
                        InUse = key;
                        Changed?.Invoke();
                    }
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        return IntPtr.Zero;
    }

    private static string? DevicePath(IntPtr device)
    {
        uint size = 0;
        GetRawInputDeviceInfo(device, RawDeviceName, null, ref size);
        if (size == 0) return null;
        var chars = new char[size];
        return GetRawInputDeviceInfo(device, RawDeviceName, chars, ref size) == unchecked((uint)-1) ? null : new string(chars).TrimEnd('\0');
    }

    /// <summary>"VID:PID" from a HID path, USB ("VID_046D&amp;PID_C52B") or Bluetooth ("VID&amp;0002046d_PID&amp;b034").</summary>
    internal static string? Key(string path)
    {
        var vendor = VendorPattern().Match(path);
        var product = ProductPattern().Match(path);
        return vendor.Success && product.Success ? $"{vendor.Groups[1].Value.ToUpperInvariant()}:{product.Groups[1].Value.ToUpperInvariant()}" : null;
    }

    [GeneratedRegex(@"VID(?:_|&\d{4})([0-9A-Fa-f]{4})")]
    private static partial Regex VendorPattern();

    [GeneratedRegex(@"PID(?:_|&)([0-9A-Fa-f]{4})")]
    private static partial Regex ProductPattern();

    internal static string Connection(string path) =>
        path.Contains("{00001124", StringComparison.OrdinalIgnoreCase) || path.Contains("BTH", StringComparison.OrdinalIgnoreCase) ? "Bluetooth" : "USB";

    private static (string Product, string Manufacturer) HidNames(string path)
    {
        using var handle = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (handle.IsInvalid) return ("Mouse", "");
        var buffer = new byte[256];
        var product = HidD_GetProductString(handle, buffer, buffer.Length) ? Text(buffer) : "Mouse";
        Array.Clear(buffer);
        var manufacturer = HidD_GetManufacturerString(handle, buffer, buffer.Length) ? Text(buffer) : "";
        return (product.Length > 0 ? product : "Mouse", manufacturer);
    }

    private static string Text(byte[] buffer) => Encoding.Unicode.GetString(buffer).TrimEnd('\0').Trim();

    public void Dispose()
    {
        window.RemoveHook(Message);
        window.Dispose();
    }
}
