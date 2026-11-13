using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using LongoMouse.Model;
using static LongoMouse.Engine.Native;

namespace LongoMouse.Engine;

/// <summary>
/// Watches the mouse through a low-level hook on a thread of its own (a hook on the UI thread would wait on layout,
/// and Windows drops a hook that's slow): buttons with actions are taken and turned into them, the wheel glides, and
/// the Double-Click Fix holds back a release that bounces. Actions are performed on another thread, in order.
/// </summary>
public sealed class MouseEngine : IDisposable
{
    private volatile EngineSettings settings = EngineSettings.Off;
    private readonly GestureTracker tracker;
    private readonly Glider glider = new();
    private readonly BlockingCollection<Action> work = new();
    private readonly Thread hookThread, workThread;
    private readonly object gate = new();
    private readonly Dictionary<bool, Timer> heldReleases = new();
    private HookProc? proc;
    private IntPtr hook;
    private uint hookThreadId;
    private DateTime lastBackForward;

    /// <summary>Any mouse input (to tell which mouse is in use, with Raw Input).</summary>
    public event Action? Input;

    public MouseEngine()
    {
        tracker = new GestureTracker(() => settings.Bindings, (seconds, action) =>
            new Timer(_ => { lock (gate) action(); }, null, TimeSpan.FromSeconds(seconds), Timeout.InfiniteTimeSpan))
        {
            DoubleClickTime = GetDoubleClickTime() / 1000.0,
        };
        tracker.Perform += (binding, delta) => work.Add(() => Actions.Perform(binding, delta));
        tracker.Replay += button => work.Add(() => Engine.Input.Click(button switch { MouseButton.Middle => 2, MouseButton.Back => 3, _ => 4 }));
        tracker.Pan += (dx, dy) => work.Add(() =>
        {
            // Grab and pan: the content follows the hand.
            Engine.Input.Wheel(dy * 3);
            Engine.Input.Wheel(-dx * 3, horizontal: true);
        });
        workThread = new Thread(() =>
        {
            foreach (var job in work.GetConsumingEnumerable())
            {
                try { job(); } catch (Exception) { /* One failed action doesn't stop the others. */ }
            }
        }) { IsBackground = true, Name = "Longo Mouse actions" };
        workThread.Start();
        hookThread = new Thread(RunHook) { IsBackground = true, Name = "Longo Mouse hook", Priority = ThreadPriority.Highest };
        hookThread.Start();
    }

    /// <summary>What to follow now; read by the hook on every event.</summary>
    public EngineSettings Settings
    {
        set
        {
            settings = value;
            if (!value.Enabled)
            {
                lock (gate) tracker.Reset();
                glider.Stop();
            }
        }
    }

    private void RunHook()
    {
        hookThreadId = GetCurrentThreadId();
        proc = Hook;
        hook = SetWindowsHookEx(MouseLowLevel, proc, GetModuleHandle(null), 0);
        while (GetMessage(out var message, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
    }

    private IntPtr Hook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code < 0) return CallNextHookEx(hook, code, wParam, lParam);
        var info = Marshal.PtrToStructure<MouseHookInfo>(lParam);
        // Ours (and other apps' made-up input) go through untouched.
        if ((info.Flags & Injected) != 0) return CallNextHookEx(hook, code, wParam, lParam);
        Input?.Invoke();
        var current = settings;
        if (!current.Enabled) return CallNextHookEx(hook, code, wParam, lParam);
        var message = (int)wParam;
        bool taken;
        try
        {
            taken = Handle(message, info, current);
        }
        catch (Exception)
        {
            taken = false;
        }
        return taken ? new IntPtr(1) : CallNextHookEx(hook, code, wParam, lParam);
    }

    private bool Handle(int message, MouseHookInfo info, EngineSettings current)
    {
        int x = info.Point.X, y = info.Point.Y;
        switch (message)
        {
            case MouseMove:
                lock (gate) return tracker.Move(x, y);
            case MiddleDown:
                glider.Stop();
                lock (gate) return tracker.Down(MouseButton.Middle, x, y);
            case MiddleUp:
                lock (gate) return tracker.Up(MouseButton.Middle);
            case XDown:
                glider.Stop();
                lock (gate) return tracker.Down(SideButton(info.MouseData), x, y);
            case XUp:
                lock (gate) return tracker.Up(SideButton(info.MouseData));
            case LeftDown or RightDown:
                glider.Stop();
                return current.ClickGuard && Bounced(message == LeftDown);
            case LeftUp or RightUp:
                return current.ClickGuard && HoldRelease(message == LeftUp, current.ClickGuardMs);
            case Wheel:
                return OnWheel((short)(info.MouseData >> 16), horizontal: false, current.Scroll);
            case HorizontalWheel:
                return OnWheel((short)(info.MouseData >> 16), horizontal: true, current.Scroll);
            default:
                return false;
        }
    }

    private static MouseButton SideButton(uint data) => (data >> 16) == 1 ? MouseButton.Back : MouseButton.Forward;

    private bool OnWheel(int delta, bool horizontal, ScrollSettings scroll)
    {
        lock (gate)
        {
            if (!horizontal && tracker.Wheel(delta)) return true;
        }
        bool control = IsDown(0x11), shift = IsDown(0x10);
        // Ctrl + wheel zooms in most apps: left to them.
        if (control && !shift) return false;
        if (!horizontal && control && shift)
        {
            if (!scroll.BackForward) return false;
            if (DateTime.UtcNow - lastBackForward >= TimeSpan.FromSeconds(0.35))
            {
                lastBackForward = DateTime.UtcNow;
                var back = delta > 0;
                work.Add(() => Engine.Input.Press(back ? 0xA6 : 0xA7));
            }
            return true;
        }
        var sideways = horizontal;
        if (!horizontal && shift && scroll.ShiftSideways)
        {
            // Wheel up scrolls left, as Shift + wheel does on the Mac.
            sideways = true;
            delta = -delta;
        }
        var factor = ScrollMath.Factor(scroll);
        if (scroll.Smooth && ScrollMath.IsNotched(delta))
        {
            var amount = delta * factor;
            glider.Add(sideways ? 0 : amount, sideways ? amount : 0, scroll.Smoothness);
            return true;
        }
        if (factor == 1 && sideways == horizontal) return false;
        // A high-resolution wheel: scaled, not glided.
        var scaled = (int)Math.Round(delta * factor);
        work.Add(() => Engine.Input.Wheel(scaled, sideways));
        return true;
    }

    /// <summary>Double-Click Fix: a release is held back a moment; a press of the same button in that time was a bounce,
    /// and both go. Otherwise the release goes on, late by that moment.</summary>
    private bool HoldRelease(bool left, int milliseconds)
    {
        lock (gate)
        {
            if (heldReleases.Remove(left, out var old))
            {
                old.Dispose();
                work.Add(() => Engine.Input.Button(left, down: false));
            }
            heldReleases[left] = new Timer(_ =>
            {
                lock (gate)
                {
                    if (!heldReleases.Remove(left, out var self)) return;
                    self.Dispose();
                }
                work.Add(() => Engine.Input.Button(left, down: false));
            }, null, milliseconds, Timeout.Infinite);
        }
        return true;
    }

    private bool Bounced(bool left)
    {
        lock (gate)
        {
            if (!heldReleases.Remove(left, out var held)) return false;
            held.Dispose();
            return true;
        }
    }

    public void Dispose()
    {
        settings = EngineSettings.Off;
        if (hookThreadId != 0) PostThreadMessage(hookThreadId, Quit, IntPtr.Zero, IntPtr.Zero);
        glider.Dispose();
        work.CompleteAdding();
        lock (gate)
        {
            foreach (var timer in heldReleases.Values) timer.Dispose();
            heldReleases.Clear();
        }
    }
}
