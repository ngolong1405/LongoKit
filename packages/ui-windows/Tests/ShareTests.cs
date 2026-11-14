using LongoKit.UI;
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
        model.SetTrusted(Phone().Info, true);
        model.SetTrusted(Phone().Info, true);
        Assert.True(model.IsTrusted(Phone().Info));
        Assert.Single(model.Trusted);
        Assert.Equal("Pixel 8", model.Trusted[0].Alias);
        model.Forget(model.Trusted[0]);
        Assert.False(model.IsTrusted(Phone().Info));
    }

    [Fact]
    public void ADeviceWithoutAFingerprintIsNeverTrusted()
    {
        var model = new ShareModel(new ShareState());
        model.SetTrusted(Phone("").Info, true);
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
    public void DevicesAroundComeFirstThenPastChats()
    {
        var state = new ShareState();
        state.Conversations["old"] = new Conversation { Id = "old", Alias = "Old Mac", Items = { new ChatItem { Text = "hi", State = ChatState.Done } } };
        var model = new ShareModel(state);
        model.Simulate(new[] { Phone() }, null);
        Assert.Equal(new[] { "f1", "old" }, model.Contacts.Select(c => c.Id));
        Assert.True(model.Contacts[0].IsOnline);
        Assert.False(model.Contacts[1].IsOnline);
        Assert.Equal("Old Mac", model.Contacts[1].Info.Alias);
    }

    [Fact]
    public void OpeningAChatReadsIt()
    {
        var state = new ShareState();
        state.Conversations["f1"] = new Conversation { Id = "f1", Alias = "Pixel 8", Unread = 3 };
        var model = new ShareModel(state);
        Assert.Equal(3, model.Unread);
        model.Selected = "f1";
        Assert.Equal(0, model.Unread);
    }

    [Fact]
    public void ClearingKeepsWhatsUnderWay()
    {
        var state = new ShareState();
        var underWay = new ChatItem();
        state.Conversations["f1"] = new Conversation
        {
            Id = "f1", Alias = "Pixel 8",
            Items = { new ChatItem { Text = "done", State = ChatState.Done }, underWay },
        };
        var model = new ShareModel(state);
        // (What was under way at launch is marked failed: this one starts now.)
        underWay.State = ChatState.Transferring;
        model.Simulate(new[] { Phone() }, "f1");
        model.Clear("f1");
        Assert.Single(model.Contact("f1")!.Conversation!.Items);
    }

    [Fact]
    public void TheMessageLine()
    {
        Localizer.Language = AppLanguage.English;
        Assert.Equal("You: photo.jpg", Words.Line(new ChatItem { Sent = true, Files = { new ChatFile { Name = "photo.jpg" } } }));
        Assert.Equal("hello", Words.Line(new ChatItem { Text = "hello" }));
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
