namespace LongoMouse.Model;

/// <summary>
/// Tells a button's click, double click, hold, drag and scroll apart, as the Mac app does (MouseEngine.swift): a hold
/// after 0.4 s, a drag past 40 px (scrolling with it, continuously), a double click within Windows' double-click time.
/// A click waits out that time only when its button has a double-click action. A gesture with no action replays the
/// button's own click, so apps still get it. Timing comes from outside (the engine's timers, a test's clock).
/// </summary>
public sealed class GestureTracker
{
    public const double HoldDelay = 0.4;
    public const double DragThreshold = 40;

    private readonly Func<IReadOnlyList<Binding>> bindings;
    private readonly Func<double, Action, IDisposable> schedule;
    private Press? press;
    private readonly Dictionary<MouseButton, IDisposable> pendingClicks = new();

    /// <summary>Windows' double-click time, in seconds.</summary>
    public double DoubleClickTime { get; set; } = 0.5;

    /// <summary>An action to perform; for scroll gestures, with the wheel's delta.</summary>
    public event Action<Binding, int>? Perform;
    /// <summary>The button's own click, for a gesture that has no action.</summary>
    public event Action<MouseButton>? Replay;
    /// <summary>Dragging to scroll: how far the pointer moved since the last move.</summary>
    public event Action<int, int>? Pan;

    private sealed class Press
    {
        public MouseButton Button;
        public int LastX, LastY;
        public double DragX, DragY;
        public bool Used, DragFired;
        public IDisposable? Hold;
    }

    /// <param name="bindings">The bindings in force now.</param>
    /// <param name="schedule">Runs an action after a delay in seconds; disposing it cancels.</param>
    public GestureTracker(Func<IReadOnlyList<Binding>> bindings, Func<double, Action, IDisposable> schedule)
    {
        this.bindings = bindings;
        this.schedule = schedule;
    }

    private Binding? Find(MouseButton button, Gesture gesture) =>
        bindings().FirstOrDefault(b => b.Button == button && b.Gesture == gesture && b.Action != MouseAction.None);

    private bool HasAny(MouseButton button) => bindings().Any(b => b.Button == button && b.Action != MouseAction.None);

    /// <summary>A button went down. Returns whether it's taken (otherwise it goes to the app as usual).</summary>
    public bool Down(MouseButton button, int x, int y)
    {
        if (!HasAny(button)) return false;
        press?.Hold?.Dispose();
        press = new Press { Button = button, LastX = x, LastY = y };
        if (Find(button, Gesture.Hold) is { } hold)
        {
            var held = press;
            held.Hold = schedule(HoldDelay, () =>
            {
                if (press != held || held.Used) return;
                held.Used = true;
                CancelPending(button);
                Perform?.Invoke(hold, 0);
            });
        }
        return true;
    }

    /// <summary>A button went up. Returns whether it's taken.</summary>
    public bool Up(MouseButton button)
    {
        if (press == null || press.Button != button) return HasAny(button);
        var done = press;
        press = null;
        done.Hold?.Dispose();
        if (done.Used) return true;
        var click = Find(button, Gesture.Click);
        if (Find(button, Gesture.DoubleClick) is not { } doubleClick)
        {
            Fire(button, click);
            return true;
        }
        if (pendingClicks.Remove(button, out var waiting))
        {
            // The second click in time: the double click, and the first click never happens.
            waiting.Dispose();
            Perform?.Invoke(doubleClick, 0);
            return true;
        }
        pendingClicks[button] = schedule(DoubleClickTime, () =>
        {
            if (pendingClicks.Remove(button)) Fire(button, click);
        });
        return true;
    }

    private void Fire(MouseButton button, Binding? click)
    {
        if (click != null) Perform?.Invoke(click, 0);
        else Replay?.Invoke(button);
    }

    private void CancelPending(MouseButton button)
    {
        if (pendingClicks.Remove(button, out var waiting)) waiting.Dispose();
    }

    /// <summary>The pointer moved. Returns whether the move is taken (dragging to scroll holds the pointer still).</summary>
    public bool Move(int x, int y)
    {
        if (press == null) return false;
        int dx = x - press.LastX, dy = y - press.LastY;
        press.LastX = x;
        press.LastY = y;
        press.DragX += dx;
        press.DragY += dy;
        if (Find(press.Button, Gesture.Drag) is not { } drag) return false;
        if (drag.Action == MouseAction.DragScroll)
        {
            press.Used = true;
            press.Hold?.Dispose();
            Pan?.Invoke(dx, dy);
            return true;
        }
        if (press.DragFired || Math.Sqrt(press.DragX * press.DragX + press.DragY * press.DragY) <= DragThreshold) return false;
        press.DragFired = true;
        press.Used = true;
        press.Hold?.Dispose();
        // Which way it went: sideways for desktops, up or down for Task View; the sign rides along.
        var sideways = Math.Abs(press.DragX) >= Math.Abs(press.DragY);
        Perform?.Invoke(drag, sideways ? Math.Sign(press.DragX) : -Math.Sign(press.DragY) * 2);
        return false;
    }

    /// <summary>The wheel turned. Returns whether it's taken by a button held with a scroll action.</summary>
    public bool Wheel(int delta)
    {
        if (press == null || Find(press.Button, Gesture.Scroll) is not { } scroll) return false;
        press.Used = true;
        press.Hold?.Dispose();
        Perform?.Invoke(scroll, delta);
        return true;
    }

    /// <summary>Forgets a press in progress (turned off, or the hook was reset).</summary>
    public void Reset()
    {
        press?.Hold?.Dispose();
        press = null;
        foreach (var waiting in pendingClicks.Values) waiting.Dispose();
        pendingClicks.Clear();
    }
}
