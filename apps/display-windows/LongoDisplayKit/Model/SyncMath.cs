namespace LongoDisplay.Model;

/// <summary>Sync's numbers, the same as the Mac app's (Engine/Displays.swift).</summary>
public static class SyncMath
{
    /// <summary>The external display's brightness when the source is at <paramref name="source"/>. A curve above 1 bends it
    /// the way light does: lower in the middle, the same at the ends.</summary>
    public static double Map(double source, double minimum, double maximum, double curve = 1)
    {
        double low = Math.Min(minimum, maximum), high = Math.Max(minimum, maximum);
        return low + Math.Pow(Math.Clamp(source, 0, 1), curve) * (high - low);
    }

    /// <summary>A laptop's brightness setting is perceptual, while a monitor's DDC brightness is close to linear in light:
    /// followed straight, a monitor at the same percentage looks far brighter at the low end. Through this curve the two
    /// look alike. Software dimming already works the way the eye does, and laptop panels like the source.</summary>
    public static double Curve(ControlMethod method) => method == ControlMethod.Ddc ? 2 : 1;

    /// <summary>Where a following display goes for <paramref name="source"/>: its range, through its curve, plus the
    /// person's own adjustment, within <paramref name="lowest"/>…1.</summary>
    public static double Target(double source, DisplaySettings settings, ControlMethod method, double lowest = 0)
    {
        var mapped = Map(source, settings.Minimum, settings.Maximum, Curve(method));
        return Math.Clamp(mapped + settings.SyncOffset, lowest, 1);
    }

    /// <summary>Without a laptop screen to follow (its lid closed, or a desktop PC), the time of day stands in for it: 0 at
    /// night, brightening from 6 to 8, 1 through the day, dimming from 17 to 21.</summary>
    public static double Daylight(double hour)
    {
        static double Ease(double x) => (1 - Math.Cos(Math.PI * Math.Clamp(x, 0, 1))) / 2;
        return hour switch
        {
            < 6 => 0,
            < 8 => Ease((hour - 6) / 2),
            < 17 => 1,
            < 21 => 1 - Ease((hour - 17) / 4),
            _ => 0,
        };
    }

    public static double Hour(DateTime time) => time.Hour + time.Minute / 60.0;

    /// <summary>Less than a step of a monitor's 0–100 brightness isn't worth a change: the light sensor's small wobbles
    /// don't make the monitors flicker.</summary>
    public const double Deadband = 0.01;

    /// <summary>One step of a display gliding to <paramref name="target"/>: a quarter of the way, at least a little, landing on
    /// it once close. About a second from end to end, at 15 steps a second.</summary>
    public static double Glide(double current, double target)
    {
        var gap = target - current;
        if (Math.Abs(gap) <= 0.008) return target;
        var step = gap * 0.25;
        return current + (Math.Abs(step) < 0.006 ? Math.Sign(gap) * 0.006 : step);
    }

    /// <summary>Brightness keys move in 16 steps, as Windows' do.</summary>
    public const double KeyStep = 1.0 / 16;

    public static double Stepped(double value, bool up, double lowest = 0)
    {
        var steps = Math.Round(value / KeyStep);
        return Math.Clamp((steps + (up ? 1 : -1)) * KeyStep, lowest, 1);
    }
}
