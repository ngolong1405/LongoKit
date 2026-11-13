using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace LongoMouse.Engine;

/// <summary>The Windows calls the engine uses: the low-level mouse hook, SendInput, Raw Input, HID names.</summary>
internal static class Native
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MouseHookInfo
    {
        public Point Point;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Message
    {
        public IntPtr Window;
        public uint Id;
        public IntPtr WParam, LParam;
        public uint Time;
        public Point Point;
    }

    public delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    public const int MouseLowLevel = 14;
    public const uint Injected = 0x1;
    public const int MouseMove = 0x200, LeftDown = 0x201, LeftUp = 0x202, RightDown = 0x204, RightUp = 0x205,
                     MiddleDown = 0x207, MiddleUp = 0x208, Wheel = 0x20A, XDown = 0x20B, XUp = 0x20C, HorizontalWheel = 0x20E;
    public const uint Quit = 0x12;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr GetModuleHandle(string? name);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern int GetMessage(out Message message, IntPtr window, uint first, uint last);

    [DllImport("user32.dll")]
    public static extern bool TranslateMessage(ref Message message);

    [DllImport("user32.dll")]
    public static extern IntPtr DispatchMessage(ref Message message);

    [DllImport("user32.dll")]
    public static extern bool PostThreadMessage(uint thread, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int key);

    [DllImport("user32.dll")]
    public static extern uint GetDoubleClickTime();

    [DllImport("winmm.dll")]
    public static extern uint timeBeginPeriod(uint milliseconds);

    [DllImport("winmm.dll")]
    public static extern uint timeEndPeriod(uint milliseconds);

    public static bool IsDown(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;

    // SendInput

    [StructLayout(LayoutKind.Sequential)]
    public struct Input
    {
        public uint Type;
        public InputUnion Data;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MouseInput
    {
        public int X, Y;
        public int MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KeyboardInput
    {
        public ushort Key;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    public const uint InputMouse = 0, InputKeyboard = 1;
    public const uint MouseLeftDown = 0x2, MouseLeftUp = 0x4, MouseRightDown = 0x8, MouseRightUp = 0x10,
                      MouseMiddleDown = 0x20, MouseMiddleUp = 0x40, MouseXDown = 0x80, MouseXUp = 0x100,
                      MouseWheel = 0x800, MouseHorizontalWheel = 0x1000;
    public const uint KeyUp = 0x2, ExtendedKey = 0x1;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint count, Input[] inputs, int size);

    // Raw Input: which mouse moved.

    [StructLayout(LayoutKind.Sequential)]
    public struct RawInputDevice
    {
        public ushort UsagePage, Usage;
        public uint Flags;
        public IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RawInputDeviceListItem
    {
        public IntPtr Device;
        public uint Type;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RawInputHeader
    {
        public uint Type, Size;
        public IntPtr Device, WParam;
    }

    public const uint RawInputSink = 0x100, RawDeviceNotify = 0x2000, RawInputCommand = 0x10000003, RawDeviceName = 0x20000007;
    public const uint TypeMouse = 0;
    public const int WmInput = 0xFF, WmInputDeviceChange = 0xFE;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterRawInputDevices(RawInputDevice[] devices, uint count, uint size);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetRawInputDeviceList([Out] RawInputDeviceListItem[]? list, ref uint count, uint size);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, char[]? data, ref uint size);

    // HID names

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);

    [DllImport("hid.dll")]
    public static extern bool HidD_GetProductString(SafeFileHandle device, byte[] buffer, int length);

    [DllImport("hid.dll")]
    public static extern bool HidD_GetManufacturerString(SafeFileHandle device, byte[] buffer, int length);
}
