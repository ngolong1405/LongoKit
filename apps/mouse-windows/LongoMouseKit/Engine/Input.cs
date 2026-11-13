using System.Runtime.InteropServices;
using static LongoMouse.Engine.Native;

namespace LongoMouse.Engine;

/// <summary>Input the app makes itself. Each is marked, so the hook lets it through instead of taking it again.</summary>
internal static class Input
{
    /// <summary>"MMAP", as the Mac app marks its own events.</summary>
    public static readonly IntPtr Signature = new(0x4D4D4150);

    private static readonly int Size = Marshal.SizeOf<Native.Input>();

    private static Native.Input Mouse(uint flags, int data = 0) =>
        new() { Type = InputMouse, Data = new InputUnion { Mouse = new MouseInput { Flags = flags, MouseData = data, ExtraInfo = Signature } } };

    private static Native.Input Key(int key, bool up)
    {
        // The arrows, Insert/Delete, Home/End, Page Up/Down and the Windows keys are extended keys.
        var extended = key is >= 0x21 and <= 0x2E or 0x5B or 0x5C;
        return new()
        {
            Type = InputKeyboard,
            Data = new InputUnion
            {
                Keyboard = new KeyboardInput { Key = (ushort)key, Flags = (up ? KeyUp : 0) | (extended ? ExtendedKey : 0), ExtraInfo = Signature },
            },
        };
    }

    private static void Send(params Native.Input[] inputs) => SendInput((uint)inputs.Length, inputs, Size);

    public static void Wheel(int delta, bool horizontal = false)
    {
        if (delta != 0) Send(Mouse(horizontal ? MouseHorizontalWheel : MouseWheel, delta));
    }

    /// <summary>Presses <paramref name="key"/> with modifiers held: Ctrl 0x11, Shift 0x10, Alt 0x12, Win 0x5B.</summary>
    public static void Press(int key, params int[] modifiers)
    {
        var inputs = new List<Native.Input>();
        foreach (var modifier in modifiers) inputs.Add(Key(modifier, false));
        inputs.Add(Key(key, false));
        inputs.Add(Key(key, true));
        foreach (var modifier in modifiers.Reverse()) inputs.Add(Key(modifier, true));
        Send(inputs.ToArray());
    }

    /// <summary>A click of the left (0), right (1), middle (2) or side buttons (3 back, 4 forward), <paramref name="times"/> times.</summary>
    public static void Click(int button, int times = 1)
    {
        var (down, up, data) = button switch
        {
            0 => (MouseLeftDown, MouseLeftUp, 0),
            1 => (MouseRightDown, MouseRightUp, 0),
            2 => (MouseMiddleDown, MouseMiddleUp, 0),
            3 => (MouseXDown, MouseXUp, 1),
            _ => (MouseXDown, MouseXUp, 2),
        };
        var inputs = new List<Native.Input>();
        for (var i = 0; i < times; i++)
        {
            inputs.Add(Mouse(down, data));
            inputs.Add(Mouse(up, data));
        }
        Send(inputs.ToArray());
    }

    /// <summary>Just one half of a click (the Double-Click Fix holds a release back, then lets it go).</summary>
    public static void Button(bool left, bool down) =>
        Send(Mouse(left ? (down ? MouseLeftDown : MouseLeftUp) : (down ? MouseRightDown : MouseRightUp)));
}
