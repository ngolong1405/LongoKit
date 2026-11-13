using LongoMouse.Model;

namespace LongoMouse.Engine;

/// <summary>What each action does on Windows, the counterpart of the Mac's (ActionPerformer.swift).</summary>
internal static class Actions
{
    private const int Control = 0x11, Shift = 0x10, Alt = 0x12, Win = 0x5B;
    private const int Left = 0x25, Right = 0x27, Tab = 0x09;
    private static DateTime lastScrollDesktop;

    /// <param name="delta">For scroll actions the wheel's turn; for drags the way it went (±1 sideways, ±2 up or down).</param>
    public static void Perform(Binding binding, int delta)
    {
        switch (binding.Action)
        {
            case MouseAction.TaskView: Input.Press(Tab, Win); break;
            case MouseAction.ShowDesktop: Input.Press('D', Win); break;
            case MouseAction.Start: Input.Press(Win); break;
            case MouseAction.DesktopLeft: Input.Press(Left, Control, Win); break;
            case MouseAction.DesktopRight: Input.Press(Right, Control, Win); break;
            case MouseAction.Back: Input.Press(0xA6); break;
            case MouseAction.Forward: Input.Press(0xA7); break;
            case MouseAction.PrimaryClick: Input.Click(0); break;
            case MouseAction.PrimaryDoubleClick: Input.Click(0, 2); break;
            case MouseAction.SecondaryClick: Input.Click(1); break;
            case MouseAction.MiddleClick: Input.Click(2); break;
            case MouseAction.Shortcut when binding.Shortcut is { } combo:
                var modifiers = new List<int>();
                if (combo.Control) modifiers.Add(Control);
                if (combo.Alt) modifiers.Add(Alt);
                if (combo.Shift) modifiers.Add(Shift);
                if (combo.Windows) modifiers.Add(Win);
                Input.Press(combo.Key, modifiers.ToArray());
                break;
            case MouseAction.PlayPause: Input.Press(0xB3); break;
            case MouseAction.NextTrack: Input.Press(0xB0); break;
            case MouseAction.PreviousTrack: Input.Press(0xB1); break;
            case MouseAction.VolumeUp: Input.Press(0xAF); break;
            case MouseAction.VolumeDown: Input.Press(0xAE); break;
            case MouseAction.Mute: Input.Press(0xAD); break;
            // Dragging right pulls the desktop on the left into view, as on the Mac.
            case MouseAction.DragDesktops when Math.Abs(delta) == 1: Input.Press(delta > 0 ? Left : Right, Control, Win); break;
            case MouseAction.DragTaskView when Math.Abs(delta) == 2:
                if (delta > 0) Input.Press(Tab, Win);
                else Input.Press('D', Win);
                break;
            case MouseAction.ScrollZoom: Input.Press(delta > 0 ? 0xBB : 0xBD, Control); break;
            case MouseAction.ScrollDesktops:
                // One desktop per flick of the wheel, not one per notch.
                if (DateTime.UtcNow - lastScrollDesktop < TimeSpan.FromSeconds(0.35)) break;
                lastScrollDesktop = DateTime.UtcNow;
                Input.Press(delta > 0 ? Left : Right, Control, Win);
                break;
            case MouseAction.ScrollHorizontal: Input.Wheel(-delta, horizontal: true); break;
        }
    }
}

/// <summary>
/// Smooth scrolling: a notch becomes a glide that eases out, sent as small turns about 120 times a second (Windows apps
/// scroll by part of a notch). Its own thread, so the hook never waits on it.
/// </summary>
internal sealed class Glider : IDisposable
{
    private readonly object gate = new();
    private readonly AutoResetEvent wake = new(false);
    private readonly Thread thread;
    private double vertical, horizontal, carryVertical, carryHorizontal, smoothness = 0.75;
    private volatile bool stopped;

    public Glider()
    {
        thread = new Thread(Run) { IsBackground = true, Name = "Longo Mouse glide", Priority = ThreadPriority.AboveNormal };
        thread.Start();
    }

    public void Add(double vertical, double horizontal, double smoothness)
    {
        lock (gate)
        {
            this.smoothness = smoothness;
            if (vertical != 0) this.vertical = ScrollMath.Add(this.vertical, vertical);
            if (horizontal != 0) this.horizontal = ScrollMath.Add(this.horizontal, horizontal);
        }
        wake.Set();
    }

    /// <summary>Stops where it is (a button pressed, the wheel touched by a trackpad).</summary>
    public void Stop()
    {
        lock (gate) vertical = horizontal = carryVertical = carryHorizontal = 0;
    }

    private void Run()
    {
        while (!stopped)
        {
            wake.WaitOne();
            if (stopped) return;
            // A 1 ms timer while gliding, for steady frames; Windows' default is 15.6 ms.
            Native.timeBeginPeriod(1);
            var clock = System.Diagnostics.Stopwatch.StartNew();
            var last = 0.0;
            while (!stopped)
            {
                Thread.Sleep(7);
                var now = clock.Elapsed.TotalSeconds;
                int stepVertical, stepHorizontal;
                bool done;
                lock (gate)
                {
                    stepVertical = ScrollMath.Step(ref vertical, ref carryVertical, now - last, smoothness);
                    stepHorizontal = ScrollMath.Step(ref horizontal, ref carryHorizontal, now - last, smoothness);
                    done = vertical == 0 && horizontal == 0 && carryVertical == 0 && carryHorizontal == 0;
                }
                last = now;
                Input.Wheel(stepVertical);
                Input.Wheel(stepHorizontal, horizontal: true);
                if (done) break;
            }
            Native.timeEndPeriod(1);
        }
    }

    public void Dispose()
    {
        stopped = true;
        wake.Set();
    }
}
