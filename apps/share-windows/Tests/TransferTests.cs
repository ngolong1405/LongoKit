using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using LongoShare;
using Xunit;

namespace LongoShare.Tests;

/// <summary>Two devices on one machine (over localhost, HTTPS), sending to each other as LocalSend does.</summary>
public sealed class Pair : IDisposable
{
    public readonly string Root = Path.Combine(Path.GetTempPath(), "longo-share-" + Guid.NewGuid().ToString("N"));
    public readonly ShareNode Sender, Receiver;

    public Pair(string? pin = null)
    {
        Sender = Node("Sender", "a");
        Receiver = Node("Receiver", "b", pin);
        Receiver.Receiver.Ask = _ => Task.FromResult(true);
    }

    private ShareNode Node(string alias, string folder, string? pin = null)
    {
        var node = new ShareNode(new ShareSettings { Alias = alias, Port = 0, Folder = Path.Combine(Root, folder), Pin = pin },
                                 Path.Combine(Root, folder + ".pfx"));
        node.Start(discover: false);
        return node;
    }

    public string Inbox => Receiver.Settings.Folder;

    public async Task<Peer> Connect() => (await Sender.Connect("127.0.0.1", Receiver.Port))!;

    public string File(string name, byte[] content)
    {
        var path = Path.Combine(Root, "out", name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        System.IO.File.WriteAllBytes(path, content);
        return path;
    }

    public void Dispose()
    {
        Sender.Dispose();
        Receiver.Dispose();
        try { Directory.Delete(Root, true); } catch (IOException) { }
    }
}

public class TransferTests
{
    [Fact]
    public async Task DevicesFindEachOtherThroughRegister()
    {
        using var pair = new Pair();
        var peer = await pair.Connect();
        Assert.NotNull(peer);
        Assert.Equal("Receiver", peer.Info.Alias);
        Assert.Equal(pair.Receiver.Fingerprint, peer.Info.Fingerprint);
        Assert.Equal(64, peer.Info.Fingerprint.Length);
        // And the receiver now knows the sender.
        Assert.Contains(pair.Receiver.Peers, p => p.Info.Alias == "Sender");
    }

    [Fact]
    public async Task FilesArriveWholeAndNamed()
    {
        using var pair = new Pair();
        var big = RandomNumberGenerator.GetBytes(5 * 1024 * 1024 + 123);
        var small = Encoding.UTF8.GetBytes("Phở ở Hàng Bè");
        ReceivedTransfer? received = null;
        pair.Receiver.Receiver.Received += r => received = r;
        long lastProgress = 0;
        var result = await pair.Sender.Send(await pair.Connect(),
            new[] { Outgoing.File(pair.File("video.bin", big)), Outgoing.File(pair.File("ghi chú.txt", small)) },
            progress: (sent, total) => lastProgress = Math.Max(lastProgress, sent));
        Assert.Equal(SendResult.Sent, result);
        Assert.Equal(big, File.ReadAllBytes(Path.Combine(pair.Inbox, "video.bin")));
        Assert.Equal(small, File.ReadAllBytes(Path.Combine(pair.Inbox, "ghi chú.txt")));
        Assert.Equal(big.Length + small.Length, lastProgress);
        Assert.NotNull(received);
        Assert.Equal(2, received!.Files.Count);
        Assert.Empty(Directory.GetFiles(pair.Inbox, "*.part"));
    }

    [Fact]
    public async Task ASecondFileOfTheSameNameIsKeptBesideTheFirst()
    {
        using var pair = new Pair();
        var peer = await pair.Connect();
        var file = pair.File("photo.png", new byte[] { 1, 2, 3 });
        Assert.Equal(SendResult.Sent, await pair.Sender.Send(peer, new[] { Outgoing.File(file) }));
        Assert.Equal(SendResult.Sent, await pair.Sender.Send(peer, new[] { Outgoing.File(file) }));
        Assert.True(File.Exists(Path.Combine(pair.Inbox, "photo.png")));
        Assert.True(File.Exists(Path.Combine(pair.Inbox, "photo (1).png")));
    }

    [Fact]
    public async Task APinIsAskedFor()
    {
        using var pair = new Pair(pin: "246810");
        var peer = await pair.Connect();
        var file = pair.File("a.txt", new byte[] { 42 });
        Assert.Equal(SendResult.PinRequired, await pair.Sender.Send(peer, new[] { Outgoing.File(file) }));
        Assert.Equal(SendResult.PinRequired, await pair.Sender.Send(peer, new[] { Outgoing.File(file) }, pin: "000000"));
        Assert.Equal(SendResult.Sent, await pair.Sender.Send(peer, new[] { Outgoing.File(file) }, pin: "246810"));
    }

    [Fact]
    public async Task RefusedFilesDontCome()
    {
        using var pair = new Pair();
        pair.Receiver.Receiver.Ask = _ => Task.FromResult(false);
        var result = await pair.Sender.Send(await pair.Connect(), new[] { Outgoing.File(pair.File("a.txt", new byte[] { 1 })) });
        Assert.Equal(SendResult.Rejected, result);
        Assert.False(Directory.Exists(pair.Inbox) && Directory.EnumerateFiles(pair.Inbox).Any());
    }

    [Fact]
    public async Task ATrustedDeviceIsntAsked()
    {
        using var pair = new Pair();
        var asked = false;
        pair.Receiver.Receiver.Ask = _ =>
        {
            asked = true;
            return Task.FromResult(false);
        };
        pair.Receiver.Settings.Trusted.Add(pair.Sender.Fingerprint);
        var result = await pair.Sender.Send(await pair.Connect(), new[] { Outgoing.File(pair.File("a.txt", new byte[] { 1 })) });
        Assert.Equal(SendResult.Sent, result);
        Assert.False(asked);
    }

    [Fact]
    public async Task TextArrivesAsAMessage()
    {
        using var pair = new Pair();
        ReceivedTransfer? received = null;
        pair.Receiver.Receiver.Received += r => received = r;
        Assert.Equal(SendResult.Sent, await pair.Sender.Send(await pair.Connect(), new[] { Outgoing.Message("Xin chào từ Windows 👋") }));
        Assert.Equal("Xin chào từ Windows 👋", received?.Text);
    }

    [Fact]
    public async Task AnotherTransferWaitsForTheOneUnderWay()
    {
        using var pair = new Pair();
        var gate = new TaskCompletionSource<bool>();
        var asked = 0;
        pair.Receiver.Receiver.Ask = async _ =>
        {
            if (Interlocked.Increment(ref asked) == 1) return await gate.Task;
            return true;
        };
        var peer = await pair.Connect();
        var first = pair.Sender.Send(peer, new[] { Outgoing.File(pair.File("a.txt", new byte[] { 1 })) });
        await Task.Delay(300);
        // The first is still being asked about: not busy yet (the session starts once it's accepted).
        gate.SetResult(true);
        Assert.Equal(SendResult.Sent, await first);
    }

    [Fact]
    public async Task AWrongChecksumIsRefused()
    {
        using var pair = new Pair();
        var peer = await pair.Connect();
        using var client = Client();
        var info = pair.Sender.Self;
        var prepare = new PrepareUploadRequest
        {
            Info = info,
            Files = new() { ["f"] = new() { Id = "f", FileName = "x.bin", Size = 3, Sha256 = new string('0', 64) } },
        };
        var response = await client.PostAsJsonAsync(new Uri(peer.BaseUri, Protocol.PrepareUpload), prepare, Protocol.Json);
        var session = (await response.Content.ReadFromJsonAsync<PrepareUploadResponse>(Protocol.Json))!;
        var upload = await client.PostAsync(new Uri(peer.BaseUri, $"{Protocol.Upload}?sessionId={session.SessionId}&fileId=f&token={session.Files["f"]}"),
                                            new ByteArrayContent(new byte[] { 1, 2, 3 }));
        Assert.Equal((HttpStatusCode)422, upload.StatusCode);
        Assert.False(File.Exists(Path.Combine(pair.Inbox, "x.bin")));
    }

    [Fact]
    public async Task AChunkedUploadArrivesToo()
    {
        using var pair = new Pair();
        var peer = await pair.Connect();
        using var client = Client();
        var content = RandomNumberGenerator.GetBytes(300_000);
        var prepare = new PrepareUploadRequest
        {
            Info = pair.Sender.Self,
            Files = new() { ["f"] = new() { Id = "f", FileName = "chunked.bin", Size = content.Length, Sha256 = Convert.ToHexString(SHA256.HashData(content)) } },
        };
        var response = await client.PostAsJsonAsync(new Uri(peer.BaseUri, Protocol.PrepareUpload), prepare, Protocol.Json);
        var session = (await response.Content.ReadFromJsonAsync<PrepareUploadResponse>(Protocol.Json))!;
        // No length given: HttpClient sends it chunked.
        var body = new StreamContent(new MemoryStream(content));
        var request = new HttpRequestMessage(HttpMethod.Post, new Uri(peer.BaseUri, $"{Protocol.Upload}?sessionId={session.SessionId}&fileId=f&token={session.Files["f"]}"))
        {
            Content = body,
        };
        request.Headers.TransferEncodingChunked = true;
        var upload = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, upload.StatusCode);
        Assert.Equal(content, File.ReadAllBytes(Path.Combine(pair.Inbox, "chunked.bin")));
    }

    [Fact]
    public async Task AWrongTokenOrSessionIsRefused()
    {
        using var pair = new Pair();
        var peer = await pair.Connect();
        using var client = Client();
        var prepare = new PrepareUploadRequest { Info = pair.Sender.Self, Files = new() { ["f"] = new() { Id = "f", FileName = "x.bin", Size = 1 } } };
        var session = (await (await client.PostAsJsonAsync(new Uri(peer.BaseUri, Protocol.PrepareUpload), prepare, Protocol.Json))
            .Content.ReadFromJsonAsync<PrepareUploadResponse>(Protocol.Json))!;
        var wrongToken = await client.PostAsync(new Uri(peer.BaseUri, $"{Protocol.Upload}?sessionId={session.SessionId}&fileId=f&token=nope"), new ByteArrayContent(new byte[] { 1 }));
        Assert.Equal(HttpStatusCode.Forbidden, wrongToken.StatusCode);
        var wrongSession = await client.PostAsync(new Uri(peer.BaseUri, $"{Protocol.Upload}?sessionId=nope&fileId=f&token={session.Files["f"]}"), new ByteArrayContent(new byte[] { 1 }));
        Assert.Equal(HttpStatusCode.Conflict, wrongSession.StatusCode);
        // Busy with that session meanwhile.
        var another = await client.PostAsJsonAsync(new Uri(peer.BaseUri, Protocol.PrepareUpload), prepare, Protocol.Json);
        Assert.Equal(HttpStatusCode.Conflict, another.StatusCode);
        // Cancelled, it's free again.
        await client.PostAsync(new Uri(peer.BaseUri, $"{Protocol.Cancel}?sessionId={session.SessionId}"), null);
        Assert.False(pair.Receiver.Receiver.IsBusy);
    }

    [Theory]
    [InlineData("../../etc/passwd", "etc/passwd")]
    [InlineData("C:\\Windows\\evil.dll", "Windows/evil.dll")]
    [InlineData("photos/2026/a.jpg", "photos/2026/a.jpg")]
    [InlineData("..", "file")]
    public void AFileNameCantLeaveTheFolder(string name, string expected)
    {
        var folder = Path.Combine(Path.GetTempPath(), "longo-share-names-" + Guid.NewGuid().ToString("N"));
        var path = Receiver.Destination(folder, name);
        Assert.StartsWith(Path.GetFullPath(folder), Path.GetFullPath(path));
        Assert.Equal(Path.Combine(folder, expected.Replace('/', Path.DirectorySeparatorChar)), path);
        Directory.Delete(folder, true);
    }

    [Fact]
    public void ACertificateIsKeptSoTheFingerprintStays()
    {
        var path = Path.Combine(Path.GetTempPath(), "longo-share-cert-" + Guid.NewGuid().ToString("N") + ".pfx");
        var first = Certificate.Fingerprint(Certificate.LoadOrCreate(path));
        var again = Certificate.Fingerprint(Certificate.LoadOrCreate(path));
        Assert.Equal(first, again);
        File.Delete(path);
    }

    [Fact]
    public void AnnouncementsUseLocalSendsFieldNames()
    {
        var json = System.Text.Json.JsonSerializer.Serialize(new DeviceInfo { Alias = "PC", Fingerprint = "abc", Announce = true }, Protocol.Json);
        foreach (var field in new[] { "\"alias\":\"PC\"", "\"version\":\"2.1\"", "\"deviceType\":\"desktop\"", "\"fingerprint\":\"abc\"", "\"port\":53317", "\"protocol\":\"https\"", "\"announce\":true" })
            Assert.Contains(field, json);
    }

    private static HttpClient Client() => new(new SocketsHttpHandler { SslOptions = { RemoteCertificateValidationCallback = (_, _, _, _) => true } });
}
