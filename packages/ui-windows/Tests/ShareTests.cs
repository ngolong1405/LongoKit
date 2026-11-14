using LongoShare;
using LongoShare.Windows;
using LongoShare.Windows.UI;
using Xunit;

namespace LongoKit.Windows.Tests;

/// <summary>Longo Share's model and how it shows things (its network side has its own tests, on every OS).</summary>
public class ShareTests
{
    private static Peer Phone(string fingerprint = "f1") =>
        new(new DeviceInfo { Alias = "Pixel 8", DeviceType = "mobile", Fingerprint = fingerprint }, "192.168.1.31");

    [Fact]
    public void ADeviceIsTrustedThenForgotten()
    {
        var model = new ShareModel(new ShareState());
        model.SetTrusted(Phone(), true);
        model.SetTrusted(Phone(), true);
        Assert.True(model.IsTrusted(Phone()));
        Assert.Single(model.Trusted);
        Assert.Equal("Pixel 8", model.Trusted[0].Alias);
        model.Forget(model.Trusted[0]);
        Assert.False(model.IsTrusted(Phone()));
    }

    [Fact]
    public void ADeviceWithoutAFingerprintIsNeverTrusted()
    {
        var model = new ShareModel(new ShareState());
        model.SetTrusted(Phone(""), true);
        Assert.Empty(model.Trusted);
    }

    [Fact]
    public void ThePinIsTrimmedAndEmptyMeansNone()
    {
        var model = new ShareModel(new ShareState());
        model.Pin = " 4821 ";
        Assert.Equal("4821", model.Pin);
        model.Pin = "  ";
        Assert.Null(model.Pin);
    }

    [Fact]
    public void AnEmptyNameIsIgnored()
    {
        var model = new ShareModel(new ShareState { Alias = "Long's PC" });
        model.Alias = "   ";
        Assert.Equal("Long's PC", model.Alias);
        model.Alias = " Desk ";
        Assert.Equal("Desk", model.Alias);
    }

    [Fact]
    public void Sizes()
    {
        Assert.Equal("512 B", Pretty.Size(512));
        Assert.Equal("1.5 KB", Pretty.Size(1536));
        Assert.Equal("58.4 MB", Pretty.Size(61_200_000));
        Assert.Equal("2 GB", Pretty.Size(2L * 1024 * 1024 * 1024));
    }

    [Fact]
    public void DevicesGetTheirGlyph()
    {
        Assert.Equal("\uE8EA", Pretty.DeviceGlyph(new DeviceInfo { DeviceType = "mobile" }));
        Assert.Equal("\uE7F8", Pretty.DeviceGlyph(new DeviceInfo { DeviceType = "desktop", DeviceModel = "macOS" }));
        Assert.Equal("\uE7F4", Pretty.DeviceGlyph(new DeviceInfo { DeviceType = "desktop", DeviceModel = "Dell" }));
    }
}
