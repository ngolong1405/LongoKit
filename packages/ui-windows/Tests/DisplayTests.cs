using LongoDisplay.Engine;
using LongoDisplay.Model;
using LongoKit.UI;
using Xunit;

namespace LongoKit.Windows.Tests;

/// <summary>Longo Display's Sync, the same checks as the Mac app's self-test.</summary>
public class SyncTests
{
    [Fact]
    public void MapsWithinTheRange()
    {
        Assert.Equal(0.5, SyncMath.Map(0.5, 0.2, 0.8), 6);
        Assert.Equal(0.3, SyncMath.Map(0, 0.3, 1), 6);
        Assert.Equal(0.6, SyncMath.Map(1, 0, 0.6), 6);
        Assert.Equal(0.9, SyncMath.Map(1, 0.9, 0.1), 6);
    }

    [Fact]
    public void AMonitorFollowsHowBrightTheLaptopLooks()
    {
        var full = new DisplaySettings { Minimum = 0, Maximum = 1 };
        Assert.Equal(0.25, SyncMath.Target(0.5, full, ControlMethod.Ddc), 6);
        Assert.Equal(0, SyncMath.Target(0, full, ControlMethod.Ddc), 6);
        Assert.Equal(1, SyncMath.Target(1, full, ControlMethod.Ddc), 6);
        Assert.Equal(0.5, SyncMath.Target(0.5, full, ControlMethod.Software), 6);
    }

    [Fact]
    public void ThePersonsAdjustmentAddsOn()
    {
        var adjusted = new DisplaySettings { SyncOffset = 0.2 };
        Assert.Equal(0.45, SyncMath.Target(0.5, adjusted, ControlMethod.Ddc), 6);
        Assert.Equal(1, SyncMath.Target(1, adjusted, ControlMethod.Ddc), 6);
    }

    [Fact]
    public void TheTimeOfDay()
    {
        Assert.Equal(0, SyncMath.Daylight(3));
        Assert.Equal(1, SyncMath.Daylight(12));
        Assert.Equal(0, SyncMath.Daylight(23));
        Assert.Equal(0.5, SyncMath.Daylight(7), 6);
        Assert.Equal(0.5, SyncMath.Daylight(19), 6);
        Assert.True(SyncMath.Daylight(6.5) < SyncMath.Daylight(7.5));
    }

    [Fact]
    public void GlidesWithoutOvershooting()
    {
        double value = 0;
        var steps = 0;
        while (value != 1 && steps < 100)
        {
            value = SyncMath.Glide(value, 1);
            Assert.True(value <= 1);
            steps++;
        }
        Assert.Equal(1, value);
        Assert.True(steps <= 30, $"{steps} steps");
    }

    [Fact]
    public void BrightnessKeysStepBySixteenths()
    {
        Assert.Equal(9.0 / 16, SyncMath.Stepped(0.5, up: true), 6);
        Assert.Equal(0, SyncMath.Stepped(0, up: false));
        Assert.Equal(1, SyncMath.Stepped(1, up: true));
        Assert.Equal(-1.0 / 16, SyncMath.Stepped(0, up: false, lowest: -DisplaySettings.MaxDim), 6);
    }

    [Fact]
    public void BelowZeroTheBacklightStaysAtZeroAndThePictureDims()
    {
        var level = new DisplaySettings();
        level.SetLevel(-0.3);
        Assert.Equal(0, level.Brightness);
        Assert.Equal(0.3, level.ExtraDim, 6);
        Assert.Equal(-0.3, level.Level, 6);
        level.SetLevel(0.4);
        Assert.Equal(0.4, level.Brightness, 6);
        Assert.Equal(0, level.ExtraDim);
        level.SetLevel(-2);
        Assert.Equal(DisplaySettings.MaxDim, level.ExtraDim);
    }
}

public class DisplayModelTests
{
    private static (DisplayModel Model, Display Laptop, Display Monitor) Sample()
    {
        var model = new DisplayModel(null, new DisplayState());
        var laptop = new Display("laptop", "Built-in", true, ControlMethod.Native, 2880, 1800);
        var monitor = new Display("lg", "LG", false, ControlMethod.Ddc, 2560, 1440) { HasDdc = true };
        model.Simulate(new[] { laptop, monitor }, new Dictionary<string, DisplaySettings>
        {
            ["laptop"] = new() { Brightness = 0.5 },
            ["lg"] = new(),
        });
        return (model, laptop, monitor);
    }

    [Fact]
    public void InSyncADisplaySetByHandKeepsFollowingAdjusted()
    {
        var (model, _, monitor) = Sample();
        model.Mode = BrightnessMode.Sync;
        model.SetLevel(monitor, 0.6);
        Assert.Equal(0.35, model.Settings(monitor).SyncOffset, 6);
        Assert.Equal(0.6, model.SyncTarget(monitor), 6);
        Assert.Equal(0.6, model.Settings(monitor).Level, 6);
        model.ResetSyncOffset(monitor);
        Assert.Equal(0, model.Settings(monitor).SyncOffset);
        Assert.Equal(0.25, model.SyncTarget(monitor), 6);
    }

    [Fact]
    public void InManualASliderJustSetsTheLevel()
    {
        var (model, _, monitor) = Sample();
        model.SetLevel(monitor, 0.6);
        Assert.Equal(0, model.Settings(monitor).SyncOffset);
        Assert.Equal(0.6, model.Settings(monitor).Level, 6);
    }

    [Fact]
    public void WithoutALaptopScreenSyncFollowsTheTimeOfDay()
    {
        var model = new DisplayModel(null, new DisplayState { Mode = BrightnessMode.Sync });
        var monitor = new Display("lg", "LG", false, ControlMethod.Ddc, 2560, 1440);
        model.Simulate(new[] { monitor }, new Dictionary<string, DisplaySettings> { ["lg"] = new() });
        Assert.Equal(SyncMath.Daylight(SyncMath.Hour(DateTime.Now)), model.SyncSource, 2);
    }

    [Fact]
    public void SoftwareDimmingDoesntGoBelowZero()
    {
        var (model, laptop, _) = Sample();
        var tv = new Display("tv", "TV", false, ControlMethod.Software, 1920, 1080);
        Assert.Equal((0.0, 1.0), model.LevelRange(tv));
        Assert.Equal((-DisplaySettings.MaxDim, 1.0), model.LevelRange(laptop));
    }
}

public class EngineTests
{
    [Fact]
    public void WmiNamesAMonitorByItsDevicePath() =>
        Assert.Equal(@"display\gsm5b7f\5&2ba4a9d&0&uid4353_0",
                     Wmi.InstanceName(@"\\?\display#gsm5b7f#5&2ba4a9d&0&uid4353#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}"));

    [Fact]
    public async Task CoalescerEndsOnTheLastValueAndSkipsStaleOnes()
    {
        var writes = new List<int>();
        var done = new TaskCompletionSource();
        var coalescer = new Coalescer<int>(value =>
        {
            Thread.Sleep(5);
            lock (writes) writes.Add(value);
            if (value == 99) done.TrySetResult();
        });
        for (var value = 0; value < 100; value++) coalescer.Submit(value);
        await done.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal(99, writes[^1]);
        Assert.True(writes.Count < 10, $"{writes.Count} writes for 100 changes");
    }
}

public class SharedTests
{
    [Fact]
    public void SettingsRoundTrip()
    {
        Store.Folder = Path.Combine(Path.GetTempPath(), "LongoKit-tests-" + Guid.NewGuid());
        var state = new DisplayState { Mode = BrightnessMode.Sync };
        state.Settings["lg"] = new DisplaySettings { Brightness = 0.4, SyncOffset = 0.1, Control = ControlChoice.Software };
        Store.Save("display", state);
        var loaded = Store.Load<DisplayState>("display");
        Assert.Equal(BrightnessMode.Sync, loaded.Mode);
        Assert.Equal(0.4, loaded.Settings["lg"].Brightness);
        Assert.Equal(0.1, loaded.Settings["lg"].SyncOffset);
        Assert.Equal(ControlChoice.Software, loaded.Settings["lg"].Control);
        Directory.Delete(Store.Folder, true);
    }

    [Fact]
    public void MissingSettingsStartFresh()
    {
        Store.Folder = Path.Combine(Path.GetTempPath(), "LongoKit-tests-" + Guid.NewGuid());
        Assert.True(Store.Load<DisplayState>("display").IsEnabled);
    }

    [Fact]
    public void LocalizerFallsBackToEnglish()
    {
        Localizer.Language = AppLanguage.Vietnamese;
        Assert.Equal("Chung", Localizer.L("General"));
        Assert.Equal("Not translated", Localizer.L("Not translated"));
        Assert.Equal("Phiên bản 1.2", Localizer.L("Version {0}", "1.2"));
        Localizer.Language = AppLanguage.English;
        Assert.Equal("General", Localizer.L("General"));
    }
}
