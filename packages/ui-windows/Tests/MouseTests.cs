using LongoMouse.Engine;
using LongoMouse.Model;
using Xunit;

namespace LongoKit.Windows.Tests;

/// <summary>Longo Mouse's gestures and wheel, the same checks as the Mac app's.</summary>
public class GestureTests
{
    /// <summary>A clock to run scheduled actions by hand.</summary>
    private sealed class Clock
    {
        private readonly List<(double At, Action Action, Cancel Token)> jobs = new();
        public double Now;

        public sealed class Cancel : IDisposable
        {
            public bool Cancelled;
            public void Dispose() => Cancelled = true;
        }

        public IDisposable Schedule(double seconds, Action action)
        {
            var token = new Cancel();
            jobs.Add((Now + seconds, action, token));
            return token;
        }

        public void Advance(double seconds)
        {
            Now += seconds;
            foreach (var job in jobs.Where(j => j.At <= Now && !j.Token.Cancelled).ToList())
            {
                jobs.Remove(job);
                job.Action();
            }
        }
    }

    private static (GestureTracker Tracker, Clock Clock, List<MouseAction> Done, List<MouseButton> Replayed) Make(params Binding[] bindings)
    {
        var clock = new Clock();
        var tracker = new GestureTracker(() => bindings, clock.Schedule) { DoubleClickTime = 0.5 };
        var done = new List<MouseAction>();
        var replayed = new List<MouseButton>();
        tracker.Perform += (binding, _) => done.Add(binding.Action);
        tracker.Replay += replayed.Add;
        return (tracker, clock, done, replayed);
    }

    private static Binding Bind(MouseButton button, Gesture gesture, MouseAction action) => new() { Button = button, Gesture = gesture, Action = action };

    [Fact]
    public void AButtonWithNoActionsIsLeftAlone()
    {
        var (tracker, _, done, _) = Make();
        Assert.False(tracker.Down(MouseButton.Back, 0, 0));
        Assert.False(tracker.Up(MouseButton.Back));
        Assert.Empty(done);
    }

    [Fact]
    public void AClickRunsAtOnceWithoutADoubleClickAction()
    {
        var (tracker, _, done, _) = Make(Bind(MouseButton.Back, Gesture.Click, MouseAction.Back));
        Assert.True(tracker.Down(MouseButton.Back, 0, 0));
        Assert.True(tracker.Up(MouseButton.Back));
        Assert.Equal(new[] { MouseAction.Back }, done);
    }

    [Fact]
    public void AHoldRunsAfterFourTenthsOfASecondAndNoClickFollows()
    {
        var (tracker, clock, done, _) = Make(Bind(MouseButton.Forward, Gesture.Click, MouseAction.Forward),
                                             Bind(MouseButton.Forward, Gesture.Hold, MouseAction.TaskView));
        tracker.Down(MouseButton.Forward, 0, 0);
        clock.Advance(0.3);
        Assert.Empty(done);
        clock.Advance(0.15);
        tracker.Up(MouseButton.Forward);
        Assert.Equal(new[] { MouseAction.TaskView }, done);
    }

    [Fact]
    public void ADoubleClickWinsOverTwoClicks()
    {
        var (tracker, clock, done, _) = Make(Bind(MouseButton.Middle, Gesture.Click, MouseAction.MiddleClick),
                                             Bind(MouseButton.Middle, Gesture.DoubleClick, MouseAction.ShowDesktop));
        tracker.Down(MouseButton.Middle, 0, 0);
        tracker.Up(MouseButton.Middle);
        clock.Advance(0.2);
        tracker.Down(MouseButton.Middle, 0, 0);
        tracker.Up(MouseButton.Middle);
        clock.Advance(1);
        Assert.Equal(new[] { MouseAction.ShowDesktop }, done);
    }

    [Fact]
    public void ASingleClickWaitsOutTheDoubleClickTime()
    {
        var (tracker, clock, done, _) = Make(Bind(MouseButton.Middle, Gesture.Click, MouseAction.MiddleClick),
                                             Bind(MouseButton.Middle, Gesture.DoubleClick, MouseAction.ShowDesktop));
        tracker.Down(MouseButton.Middle, 0, 0);
        tracker.Up(MouseButton.Middle);
        clock.Advance(0.4);
        Assert.Empty(done);
        clock.Advance(0.2);
        Assert.Equal(new[] { MouseAction.MiddleClick }, done);
    }

    [Fact]
    public void AGestureWithNoActionReplaysTheButtonsOwnClick()
    {
        var (tracker, _, done, replayed) = Make(Bind(MouseButton.Back, Gesture.Hold, MouseAction.TaskView));
        tracker.Down(MouseButton.Back, 0, 0);
        tracker.Up(MouseButton.Back);
        Assert.Empty(done);
        Assert.Equal(new[] { MouseButton.Back }, replayed);
    }

    [Fact]
    public void ADragRunsOncePastFortyPixelsTheWayItWent()
    {
        var clock = new Clock();
        var drag = Bind(MouseButton.Middle, Gesture.Drag, MouseAction.DragDesktops);
        var tracker = new GestureTracker(() => new[] { drag }, clock.Schedule);
        var ways = new List<int>();
        tracker.Perform += (_, way) => ways.Add(way);
        tracker.Down(MouseButton.Middle, 100, 100);
        tracker.Move(130, 102);
        Assert.Empty(ways);
        tracker.Move(160, 104);
        tracker.Move(220, 104);
        tracker.Up(MouseButton.Middle);
        Assert.Equal(new[] { 1 }, ways);
    }

    [Fact]
    public void GrabToScrollPansAndHoldsThePointer()
    {
        var clock = new Clock();
        var tracker = new GestureTracker(() => new[] { Bind(MouseButton.Middle, Gesture.Drag, MouseAction.DragScroll) }, clock.Schedule);
        var pans = new List<(int, int)>();
        tracker.Pan += (dx, dy) => pans.Add((dx, dy));
        tracker.Down(MouseButton.Middle, 0, 0);
        Assert.True(tracker.Move(5, -3));
        Assert.Equal(new[] { (5, -3) }, pans);
    }

    [Fact]
    public void AWheelTurnWhileHoldingIsTheButtonsScrollAction()
    {
        var (tracker, _, done, _) = Make(Bind(MouseButton.Back, Gesture.Scroll, MouseAction.ScrollZoom));
        Assert.False(tracker.Wheel(120));
        tracker.Down(MouseButton.Back, 0, 0);
        Assert.True(tracker.Wheel(120));
        Assert.True(tracker.Up(MouseButton.Back));
        Assert.Equal(new[] { MouseAction.ScrollZoom }, done);
    }
}

public class WheelTests
{
    [Fact]
    public void AGlideLastsTwoHundredToAThousandMilliseconds()
    {
        Assert.Equal(0.2, ScrollMath.Duration(0), 6);
        Assert.Equal(1.0, ScrollMath.Duration(1), 6);
        Assert.Equal(0.8, ScrollMath.Duration(0.75), 6);
    }

    [Fact]
    public void OnlyWholeNotchesGlide()
    {
        Assert.True(ScrollMath.IsNotched(120));
        Assert.True(ScrollMath.IsNotched(-240));
        Assert.False(ScrollMath.IsNotched(30));
        Assert.False(ScrollMath.IsNotched(0));
    }

    [Fact]
    public void DirectionAndSpeed()
    {
        Assert.Equal(1, ScrollMath.Factor(new ScrollSettings()));
        Assert.Equal(-1, ScrollMath.Factor(new ScrollSettings { Natural = true }));
        Assert.Equal(1.5, ScrollMath.Factor(new ScrollSettings { Speed = 1.5 }));
        Assert.Equal(1, ScrollMath.Factor(new ScrollSettings { Speed = 1.5, CustomSpeed = false }));
    }

    [Fact]
    public void TurningTheOtherWayDropsWhatWasLeft()
    {
        Assert.Equal(-120, ScrollMath.Add(300, -120));
        Assert.Equal(420, ScrollMath.Add(300, 120));
        Assert.Equal(ScrollMath.MaxGlide, ScrollMath.Add(ScrollMath.MaxGlide, 120));
    }

    [Fact]
    public void AGlideSendsTheWholeNotchEasingOut()
    {
        double remaining = 120, carry = 0;
        var sent = new List<int>();
        for (var frame = 0; frame < 400 && (remaining != 0 || carry != 0); frame++)
            sent.Add(ScrollMath.Step(ref remaining, ref carry, 1.0 / 120, 0.75));
        Assert.Equal(120, sent.Sum());
        // Ease-out: more at the start than at the end.
        Assert.True(sent[0] > sent[^1]);
        Assert.True(sent.Count < 200, $"{sent.Count} frames");
    }
}

public class MouseModelTests
{
    private static MouseModel Sample()
    {
        var model = new MouseModel(null, null, new MouseState());
        model.Simulate(new[] { new MouseDevice("046D:B034", "MX Master 3S", "Logitech", "Bluetooth"), new MouseDevice("1532:0099", "DeathAdder", "Razer", "USB") }, "046D:B034");
        return model;
    }

    [Fact]
    public void BackAndForwardOnTheSideButtonsByDefault()
    {
        var model = Sample();
        Assert.Equal(MouseAction.Back, model.ActionOf(null, MouseButton.Back, Gesture.Click));
        Assert.Equal(MouseAction.Forward, model.ActionOf(null, MouseButton.Forward, Gesture.Click));
    }

    [Fact]
    public void AMouseWithItsOwnScrollingKeepsIt()
    {
        var model = Sample();
        model.SetOwnScroll("1532:0099", true);
        model.SetScroll("1532:0099", s => s.Natural = true);
        Assert.True(model.Scroll("1532:0099").Natural);
        Assert.False(model.Scroll(null).Natural);
        model.SetOwnScroll("1532:0099", false);
        Assert.False(model.Scroll("1532:0099").Natural);
    }

    [Fact]
    public void OwnButtonsStartAsACopyOfTheShared()
    {
        var model = Sample();
        model.SetOwnButtons("1532:0099", true);
        model.SetAction("1532:0099", MouseButton.Back, Gesture.Click, MouseAction.TaskView);
        Assert.Equal(MouseAction.TaskView, model.ActionOf("1532:0099", MouseButton.Back, Gesture.Click));
        Assert.Equal(MouseAction.Back, model.ActionOf(null, MouseButton.Back, Gesture.Click));
        Assert.Equal(MouseAction.Forward, model.ActionOf("1532:0099", MouseButton.Forward, Gesture.Click));
    }

    [Fact]
    public void TheEngineFollowsTheMouseInUse()
    {
        var model = Sample();
        model.SetOwnScroll("046D:B034", true);
        model.SetScroll("046D:B034", s => s.Speed = 2);
        Assert.Equal(2, model.Effective.Scroll.Speed);
        model.AutoSwitch = false;
        Assert.Equal(1, model.Effective.Scroll.Speed);
    }

    [Fact]
    public void NothingRemovesAGesture()
    {
        var model = Sample();
        model.SetAction(null, MouseButton.Back, Gesture.Click, MouseAction.None);
        Assert.DoesNotContain(model.Bindings(null), b => b.Button == MouseButton.Back && b.Gesture == Gesture.Click);
    }
}

public class MiceTests
{
    [Fact]
    public void AUsbMouseIsKnownByVendorAndProduct() =>
        Assert.Equal("046D:C52B", Mice.Key(@"\\?\HID#VID_046D&PID_C52B&MI_01&Col01#8&2a0b3e7&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}"));

    [Fact]
    public void ABluetoothMouseToo() =>
        Assert.Equal("046D:B034", Mice.Key(@"\\?\HID#{00001124-0000-1000-8000-00805f9b34fb}_VID&0002046d_PID&b034&Col01#9&1c5c1e4&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}"));

    [Fact]
    public void BluetoothIsToldFromUsb()
    {
        Assert.Equal("Bluetooth", Mice.Connection(@"\\?\HID#{00001124-0000-1000-8000-00805f9b34fb}_VID&0002046d_PID&b034"));
        Assert.Equal("USB", Mice.Connection(@"\\?\HID#VID_046D&PID_C52B&MI_01"));
    }
}
