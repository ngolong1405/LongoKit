using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using static LongoShot.Engine.Native;

namespace LongoShot.Engine;

/// <summary>A monitor: where it is in screen pixels, and its scale (1.5 at 150%).</summary>
public sealed record Screen(IntPtr Handle, Int32Rect Bounds, Int32Rect Work, double Scale, bool IsPrimary)
{
    /// <summary>The screen under the pointer.</summary>
    public static Screen? UnderPointer(IReadOnlyList<Screen> screens)
    {
        GetCursorPos(out var point);
        return screens.FirstOrDefault(s => point.X >= s.Bounds.X && point.X < s.Bounds.X + s.Bounds.Width &&
                                           point.Y >= s.Bounds.Y && point.Y < s.Bounds.Y + s.Bounds.Height) ?? screens.FirstOrDefault();
    }
}

/// <summary>A screen as it was when the shortcut was pressed: its picture, at its own pixels.</summary>
public sealed record Frozen(Screen Screen, BitmapSource Picture);

/// <summary>A window on screen, for picking one: its frame in screen pixels, frontmost first.</summary>
public sealed record WindowFrame(IntPtr Handle, Int32Rect Bounds);

/// <summary>The monitors and what's on them, read straight from Windows (GDI): a screen in a few milliseconds.</summary>
public static class Screens
{
    public static IReadOnlyList<Screen> All()
    {
        var screens = new List<Screen>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr monitor, IntPtr _, ref Native.Rect _, IntPtr _) =>
        {
            var info = new MonitorInfoEx { Size = Marshal.SizeOf<MonitorInfoEx>() };
            if (!GetMonitorInfo(monitor, ref info)) return true;
            var scale = GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 ? dpi / 96.0 : 1;
            screens.Add(new Screen(monitor, new Int32Rect(info.Monitor.Left, info.Monitor.Top, info.Monitor.Width, info.Monitor.Height),
                                   new Int32Rect(info.Work.Left, info.Work.Top, info.Work.Width, info.Work.Height), scale, (info.Flags & 1) != 0));
            return true;
        }, IntPtr.Zero);
        return screens;
    }

    /// <summary>Every screen right now, before anything of Shot's shows.</summary>
    public static IReadOnlyList<Frozen> Freeze() => All().Select(screen => new Frozen(screen, Copy(screen.Bounds))).ToList();

    /// <summary>The pixels of <paramref name="area"/> (screen pixels), as one frozen picture.</summary>
    public static BitmapSource Copy(Int32Rect area)
    {
        var screen = GetDC(IntPtr.Zero);
        var memory = CreateCompatibleDC(screen);
        var bitmap = CreateCompatibleBitmap(screen, area.Width, area.Height);
        var old = SelectObject(memory, bitmap);
        try
        {
            // CAPTUREBLT takes layered windows (menus, tooltips) too.
            BitBlt(memory, 0, 0, area.Width, area.Height, screen, area.X, area.Y, SourceCopy | CaptureBlt);
            SelectObject(memory, old);
            var picture = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(bitmap, IntPtr.Zero, Int32Rect.Empty,
                                                                                        BitmapSizeOptions.FromEmptyOptions());
            picture.Freeze();
            return picture;
        }
        finally
        {
            DeleteObject(bitmap);
            DeleteDC(memory);
            ReleaseDC(IntPtr.Zero, screen);
        }
    }

    /// <summary>The windows on screen, frontmost first, without the desktop, the taskbar's own or Shot's.</summary>
    public static IReadOnlyList<WindowFrame> Windows()
    {
        var own = (uint)Environment.ProcessId;
        var windows = new List<WindowFrame>();
        var name = new System.Text.StringBuilder(64);
        EnumWindows((window, _) =>
        {
            if (!IsWindowVisible(window) || IsIconic(window)) return true;
            if (DwmGetWindowAttribute(window, Cloaked, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            GetWindowThreadProcessId(window, out var process);
            if (process == own) return true;
            name.Clear();
            GetClassName(window, name, name.Capacity);
            var type = name.ToString();
            if (type is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return true;
            if (DwmGetWindowAttribute(window, ExtendedFrameBounds, out Native.Rect frame, Marshal.SizeOf<Native.Rect>()) != 0) return true;
            if (frame.Width < 40 || frame.Height < 40) return true;
            windows.Add(new WindowFrame(window, new Int32Rect(frame.Left, frame.Top, frame.Width, frame.Height)));
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    /// <summary><paramref name="area"/> (pixels of the picture) cut from <paramref name="picture"/>; shares its pixels.</summary>
    public static BitmapSource Cut(BitmapSource picture, Int32Rect area)
    {
        var clipped = Clip(area, picture.PixelWidth, picture.PixelHeight);
        if (clipped.Width <= 0 || clipped.Height <= 0) return picture;
        var cut = new CroppedBitmap(picture, clipped);
        cut.Freeze();
        return cut;
    }

    /// <summary><paramref name="area"/> kept inside a picture <paramref name="width"/> × <paramref name="height"/>.</summary>
    public static Int32Rect Clip(Int32Rect area, int width, int height)
    {
        int left = Math.Clamp(area.X, 0, width), top = Math.Clamp(area.Y, 0, height);
        int right = Math.Clamp(area.X + area.Width, 0, width), bottom = Math.Clamp(area.Y + area.Height, 0, height);
        return new Int32Rect(left, top, Math.Max(right - left, 0), Math.Max(bottom - top, 0));
    }
}
