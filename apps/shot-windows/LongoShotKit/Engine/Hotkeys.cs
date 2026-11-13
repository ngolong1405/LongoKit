using System.Windows.Interop;
using static LongoShot.Engine.Native;

namespace LongoShot.Engine;

/// <summary>A key combination that works in any app.</summary>
public sealed record Hotkey(uint Modifiers, uint Key)
{
    public string Name
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & ModControl) != 0) parts.Add("Ctrl");
            if ((Modifiers & ModAlt) != 0) parts.Add("Alt");
            if ((Modifiers & ModShift) != 0) parts.Add("Shift");
            if ((Modifiers & ModWin) != 0) parts.Add("Win");
            parts.Add(Key is >= 0x30 and <= 0x5A ? ((char)Key).ToString() : Key is >= 0x70 and <= 0x87 ? "F" + (Key - 0x6F) : $"0x{Key:X2}");
            return string.Join("+", parts);
        }
    }

    public static Hotkey AltShift(char key) => new(ModAlt | ModShift, key);
}

/// <summary>Global hot keys, through a message-only window: Windows tells it when one is pressed.</summary>
public sealed class Hotkeys : IDisposable
{
    private readonly HwndSource window;
    private readonly Dictionary<int, Action> actions = new();
    private int next = 1;

    public Hotkeys()
    {
        window = new HwndSource(new HwndSourceParameters("Longo Shot hot keys") { ParentWindow = new IntPtr(-3), WindowStyle = 0 });
        window.AddHook((IntPtr _, int message, IntPtr wParam, IntPtr _, ref bool handled) =>
        {
            if (message == WmHotKey && actions.TryGetValue(wParam.ToInt32(), out var action))
            {
                handled = true;
                action();
            }
            return IntPtr.Zero;
        });
    }

    /// <summary>Registers <paramref name="hotkey"/>; false if another app holds it.</summary>
    public bool Add(Hotkey hotkey, Action action)
    {
        var id = next++;
        if (!RegisterHotKey(window.Handle, id, hotkey.Modifiers | ModNoRepeat, hotkey.Key)) return false;
        actions[id] = action;
        return true;
    }

    public void Clear()
    {
        foreach (var id in actions.Keys) UnregisterHotKey(window.Handle, id);
        actions.Clear();
    }

    public void Dispose()
    {
        Clear();
        window.Dispose();
    }
}
