using System.Net;
using System.Net.Http.Json;
using System.Text;

namespace LongoShare;

/// <summary>Why a transfer didn't go.</summary>
public enum SendResult { Sent, PinRequired, Rejected, Busy, Failed, Cancelled }

/// <summary>Something to send: a file on disk, or text.</summary>
public sealed record Outgoing(string? Path = null, string? Text = null)
{
    public static Outgoing File(string path) => new(path);
    public static Outgoing Message(string text) => new(Text: text);
}

/// <summary>
/// The sending side of LocalSend: prepare-upload, then each file streamed from disk (three at a time), with progress
/// and cancel. Certificates are self-signed, as everywhere in LocalSend, so any is accepted; the fingerprint names it.
/// </summary>
public sealed class Sender : IDisposable
{
    private readonly HttpClient client;
    private readonly Func<DeviceInfo> self;

    public Sender(Func<DeviceInfo> self)
    {
        this.self = self;
        var handler = new SocketsHttpHandler
        {
            SslOptions = { RemoteCertificateValidationCallback = (_, _, _, _) => true },
            ConnectTimeout = TimeSpan.FromSeconds(4),
            PooledConnectionIdleTimeout = TimeSpan.FromSeconds(30),
        };
        // Uploads take as long as they take; requests without a body don't.
        client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
    }

    /// <summary>Tells <paramref name="address"/> about this device; its answer says who it is (null if nothing answers).</summary>
    public async Task<Peer?> Register(string address, int port, string protocol, CancellationToken token = default)
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(2));
            var uri = new Peer(new DeviceInfo { Port = port, Protocol = protocol }, address).BaseUri;
            using var response = await client.PostAsJsonAsync(new Uri(uri, Protocol.Register), self() with { Announce = null }, Protocol.Json, timeout.Token);
            if (!response.IsSuccessStatusCode) return null;
            var info = await response.Content.ReadFromJsonAsync<DeviceInfo>(Protocol.Json, timeout.Token);
            return info == null ? null : new Peer(info with { Port = port, Protocol = protocol }, address);
        }
        catch (Exception) when (!token.IsCancellationRequested)
        {
            return null;
        }
    }

    /// <summary>Sends <paramref name="items"/> to <paramref name="peer"/>. <paramref name="progress"/> gets bytes sent and the total.</summary>
    public async Task<SendResult> Send(Peer peer, IReadOnlyList<Outgoing> items, string? pin = null,
                                       Action<long, long>? progress = null, CancellationToken token = default)
    {
        var files = new Dictionary<string, FileInfo>();
        var sources = new Dictionary<string, Outgoing>();
        foreach (var item in items)
        {
            var id = Guid.NewGuid().ToString("N");
            sources[id] = item;
            if (item.Text is { } text)
            {
                files[id] = new FileInfo { Id = id, FileName = id + ".txt", Size = Encoding.UTF8.GetByteCount(text), FileType = "text/plain", Preview = text };
                continue;
            }
            var info = new System.IO.FileInfo(item.Path!);
            files[id] = new FileInfo
            {
                Id = id, FileName = info.Name, Size = info.Length, FileType = MimeType(info.Extension),
                Metadata = new FileMetadata { Modified = info.LastWriteTimeUtc, Accessed = info.LastAccessTimeUtc },
            };
        }
        var prepare = new Uri(peer.BaseUri, Protocol.PrepareUpload + (string.IsNullOrEmpty(pin) ? "" : "?pin=" + Uri.EscapeDataString(pin)));
        PrepareUploadResponse? session;
        try
        {
            using var response = await client.PostAsJsonAsync(prepare, new PrepareUploadRequest { Info = self(), Files = files }, Protocol.Json, token);
            switch (response.StatusCode)
            {
                case HttpStatusCode.NoContent: return SendResult.Sent;
                case HttpStatusCode.Unauthorized: return SendResult.PinRequired;
                case HttpStatusCode.Forbidden: return SendResult.Rejected;
                case HttpStatusCode.Conflict: return SendResult.Busy;
                case HttpStatusCode.OK: break;
                default: return SendResult.Failed;
            }
            session = await response.Content.ReadFromJsonAsync<PrepareUploadResponse>(Protocol.Json, token);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            return SendResult.Cancelled;
        }
        catch (Exception)
        {
            return SendResult.Failed;
        }
        if (session == null) return SendResult.Failed;

        var total = files.Values.Where(f => session.Files.ContainsKey(f.Id)).Sum(f => f.Size);
        long sent = 0;
        using var gate = new SemaphoreSlim(3);
        try
        {
            var uploads = session.Files.Select(async pair =>
            {
                await gate.WaitAsync(token);
                try
                {
                    var (id, fileToken) = pair;
                    var uri = new Uri(peer.BaseUri, $"{Protocol.Upload}?sessionId={Uri.EscapeDataString(session.SessionId)}&fileId={Uri.EscapeDataString(id)}&token={Uri.EscapeDataString(fileToken)}");
                    Stream source = sources[id].Text is { } text ? new MemoryStream(Encoding.UTF8.GetBytes(text)) : File.OpenRead(sources[id].Path!);
                    await using var _ = source;
                    var content = new StreamContent(new Counting(source, read => progress?.Invoke(Interlocked.Add(ref sent, read), total)), 1 << 16);
                    content.Headers.ContentLength = files[id].Size;
                    content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
                    using var response = await client.PostAsync(uri, content, token);
                    return response.IsSuccessStatusCode;
                }
                finally
                {
                    gate.Release();
                }
            }).ToList();
            var results = await Task.WhenAll(uploads);
            return results.All(ok => ok) ? SendResult.Sent : SendResult.Failed;
        }
        catch (Exception) when (token.IsCancellationRequested)
        {
            await CancelOn(peer, session.SessionId);
            return SendResult.Cancelled;
        }
        catch (Exception)
        {
            await CancelOn(peer, session.SessionId);
            return SendResult.Failed;
        }
    }

    private async Task CancelOn(Peer peer, string sessionId)
    {
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            using var _ = await client.PostAsync(new Uri(peer.BaseUri, $"{Protocol.Cancel}?sessionId={Uri.EscapeDataString(sessionId)}"), null, timeout.Token);
        }
        catch (Exception)
        {
            // It may be gone already.
        }
    }

    internal static string MimeType(string extension) => extension.ToLowerInvariant() switch
    {
        ".png" => "image/png", ".jpg" or ".jpeg" => "image/jpeg", ".gif" => "image/gif", ".webp" => "image/webp", ".heic" => "image/heic",
        ".mp4" => "video/mp4", ".mov" => "video/quicktime", ".mp3" => "audio/mpeg", ".m4a" => "audio/mp4",
        ".pdf" => "application/pdf", ".zip" => "application/zip", ".txt" => "text/plain", ".json" => "application/json",
        ".apk" => "application/vnd.android.package-archive",
        _ => "application/octet-stream",
    };

    public void Dispose() => client.Dispose();

    /// <summary>A stream that says how much was read from it, for progress.</summary>
    private sealed class Counting : Stream
    {
        private readonly Stream inner;
        private readonly Action<int> read;

        public Counting(Stream inner, Action<int> read)
        {
            this.inner = inner;
            this.read = read;
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default)
        {
            var count = await inner.ReadAsync(buffer, token);
            if (count > 0) read(count);
            return count;
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            var done = inner.Read(buffer, offset, count);
            if (done > 0) read(done);
            return done;
        }

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => inner.Length;
        public override long Position { get => inner.Position; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
