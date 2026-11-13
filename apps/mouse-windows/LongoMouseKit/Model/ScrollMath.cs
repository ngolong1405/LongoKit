namespace LongoMouse.Model;

/// <summary>The smooth scrolling numbers, the same as the Mac app's (MouseEngine.swift).</summary>
public static class ScrollMath
{
    /// <summary>One notch of the wheel, in Windows' units.</summary>
    public const int Notch = 120;
    /// <summary>The most a glide holds per axis (about 33 notches), so a fling can't run away.</summary>
    public const double MaxGlide = 4000;

    /// <summary>A glide's length: 200 ms to 1000 ms.</summary>
    public static double Duration(double smoothness) => 0.2 + 0.8 * Math.Clamp(smoothness, 0, 1);

    /// <summary>The share of what's left to scroll in a frame <paramref name="elapsed"/> seconds long: an exponential
    /// ease-out, like Lenis' lerp.</summary>
    public static double Share(double elapsed, double smoothness) => 1 - Math.Exp(-elapsed / (Duration(smoothness) / 4));

    /// <summary>The factor a notch is scaled by: direction, then speed when it applies.</summary>
    public static double Factor(ScrollSettings scroll) => (scroll.Natural ? -1 : 1) * (scroll.CustomSpeed ? Math.Clamp(scroll.Speed, 0.5, 2) : 1);

    /// <summary>A notched wheel sends whole notches; a high-resolution wheel or a touchpad sends pieces, left as they are.</summary>
    public static bool IsNotched(int delta) => delta != 0 && delta % Notch == 0;

    /// <summary>What's left to glide after adding <paramref name="delta"/>: turning the other way drops what was left.</summary>
    public static double Add(double remaining, double delta)
    {
        if (remaining != 0 && Math.Sign(remaining) != Math.Sign(delta)) remaining = 0;
        return Math.Clamp(remaining + delta, -MaxGlide, MaxGlide);
    }

    /// <summary>One frame of a glide: how much to scroll now, carrying what doesn't make a whole unit to the next frame.
    /// Returns the units to send and updates <paramref name="remaining"/> and <paramref name="carry"/>.</summary>
    public static int Step(ref double remaining, ref double carry, double elapsed, double smoothness)
    {
        var move = Math.Abs(remaining) < 1 ? remaining : remaining * Share(elapsed, smoothness);
        remaining -= move;
        carry += move;
        var whole = (int)Math.Truncate(carry);
        carry -= whole;
        if (remaining == 0 && Math.Abs(carry) < 1) carry = 0;
        return whole;
    }
}
