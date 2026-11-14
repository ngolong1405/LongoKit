using System.Net;
using System.Security.Cryptography;
using System.Text.Json;

namespace LongoShare;

/// <summary>Files someone wants to send, waiting for an answer.</summary>
public sealed record IncomingTransfer(Peer From, IReadOnlyList<FileInfo> Files)
{
    /// <summary>A message rather than files: text sent on its own (LocalSend sends it as a file with its text as preview).</summary>
    public string? Text => Files.Count == 1 && Files[0].FileType.StartsWith("text/", StringComparison.Ordinal) && Files[0].Preview is { } text ? text : null;
}

/// <summary>A received transfer, done: the files saved, where.</summary>
public sealed record ReceivedTransfer(Peer From, IReadOnlyList<string> Files, string? Text);

/// <summary>
/// The receiving side of LocalSend: answers /register and /info, asks before accepting files (or takes them from a
/// trusted device at once), checks the PIN, and writes each upload straight to disk, checking its SHA-256 on the way.
/// One transfer at a time, as LocalSend does: another one meanwhile is told to wait (409).
/// </summary>
public sealed class Receiver
{
    private readonly Func<DeviceInfo> self;
    private readonly object gate = new();
    private Session? session;

    /// <summary>Asks the person whether to take files; true takes them.</summary>
    public Func<IncomingTransfer, Task<bool>> Ask { get; set; } = _ => Task.FromResult(false);
    /// <summary>A device announced itself (or answered): it's on the network.</summary>
    public event Action<Peer>? Registered;
    /// <summary>Files are on their way in (asked and accepted, or from a trusted device).</summary>
    public event Action<IncomingTransfer>? Accepted;
    /// <summary>Bytes received so far of a transfer, and its total.</summary>
    public event Action<long, long>? Progress;
    public event Action<ReceivedTransfer>? Received;
    /// <summary>The sender cancelled, or a file failed.</summary>
    public event Action? Cancelled;

    /// <summary>Where files go.</summary>
    public string Folder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    /// <summary>A PIN senders must give, or null.</summary>
    public string? Pin { get; set; }
    /// <summary>Devices whose files are taken without asking, by fingerprint.</summary>
    public HashSet<string> Trusted { get; set; } = new();

    private sealed class Session
    {
        public string Id = Guid.NewGuid().ToString("N");
        public required Peer From;
        public required IPAddress Address;
        public required Dictionary<string, FileInfo> Files;
        public required Dictionary<string, string> Tokens;
        public readonly Dictionary<string, string> Saved = new();
        public readonly List<string> Partial = new();
        public long Total, Done;
    }

    public Receiver(Func<DeviceInfo> self) => this.self = self;

    public bool IsBusy
    {
        get { lock (gate) return session != null; }
    }

    public async Task<HttpResponse> Handle(HttpRequest request)
    {
        switch (request.Path)
        {
            case Protocol.Register when request.Method == "POST":
                if (await Read<DeviceInfo>(request) is { } device) Registered?.Invoke(new Peer(device, request.Remote.ToString()));
                return HttpResponse.Ok(self() with { Announce = null });
            case Protocol.Info:
                return HttpResponse.Ok(self() with { Announce = null });
            case Protocol.PrepareUpload when request.Method == "POST":
                return await Prepare(request);
            case Protocol.Upload when request.Method == "POST":
                return await Upload(request);
            case Protocol.Cancel when request.Method == "POST":
                Cancel(request["sessionId"]);
                return HttpResponse.Empty;
            default:
                return new HttpResponse(404);
        }
    }

    private static async Task<T?> Read<T>(HttpRequest request) where T : class
    {
        try
        {
            return await JsonSerializer.DeserializeAsync<T>(request.Body, Protocol.Json);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private async Task<HttpResponse> Prepare(HttpRequest request)
    {
        if (await Read<PrepareUploadRequest>(request) is not { } prepare) return new HttpResponse(400);
        if (Pin is { Length: > 0 } pin && request["pin"] != pin) return new HttpResponse(401);
        if (IsBusy) return new HttpResponse(409);
        var from = new Peer(prepare.Info, request.Remote.ToString());
        Registered?.Invoke(from);
        var files = prepare.Files.Values.ToList();
        var incoming = new IncomingTransfer(from, files);
        var trusted = !string.IsNullOrEmpty(prepare.Info.Fingerprint) && Trusted.Contains(prepare.Info.Fingerprint);
        if (!trusted && !await Ask(incoming)) return new HttpResponse(403);
        // A message alone: nothing to upload.
        if (incoming.Text is { } text)
        {
            Received?.Invoke(new ReceivedTransfer(from, Array.Empty<string>(), text));
            return new HttpResponse(204);
        }
        if (files.Count == 0) return new HttpResponse(204);
        Accepted?.Invoke(incoming);
        Session started;
        lock (gate)
        {
            if (session != null) return new HttpResponse(409);
            session = started = new Session
            {
                From = from,
                Address = request.Remote,
                Files = prepare.Files,
                Tokens = prepare.Files.Keys.ToDictionary(id => id, _ => Convert.ToHexString(RandomNumberGenerator.GetBytes(16))),
                Total = files.Sum(f => f.Size),
            };
        }
        return HttpResponse.Ok(new PrepareUploadResponse { SessionId = started.Id, Files = started.Tokens });
    }

    private async Task<HttpResponse> Upload(HttpRequest request)
    {
        string? sessionId = request["sessionId"], fileId = request["fileId"], token = request["token"];
        if (sessionId == null || fileId == null || token == null) return new HttpResponse(400);
        Session? current;
        lock (gate) current = session;
        if (current == null || current.Id != sessionId) return new HttpResponse(409);
        if (!current.Tokens.TryGetValue(fileId, out var expected) || expected != token || !current.Address.Equals(request.Remote)) return new HttpResponse(403);
        var file = current.Files[fileId];
        var target = Destination(Folder, file.FileName);
        var partial = target + ".part";
        lock (gate) current.Partial.Add(partial);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        try
        {
            await using (var output = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true))
            {
                var buffer = new byte[1 << 16];
                int read;
                while ((read = await request.Body.ReadAsync(buffer)) > 0)
                {
                    await output.WriteAsync(buffer.AsMemory(0, read));
                    if (file.Sha256 != null) hash.AppendData(buffer, 0, read);
                    long done;
                    lock (gate) done = current.Done += read;
                    Progress?.Invoke(done, current.Total);
                }
            }
            if (file.Sha256 is { } sha && !string.Equals(Convert.ToHexString(hash.GetHashAndReset()), sha, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(partial);
                return new HttpResponse(422);
            }
            if (file.Metadata?.Modified is { } modified) File.SetLastWriteTimeUtc(partial, modified.UtcDateTime);
            // Its name was kept for it while it came in; only another file taking it meanwhile moves it to a new one.
            if (File.Exists(target)) target = Destination(Folder, file.FileName);
            File.Move(partial, target);
        }
        catch (Exception)
        {
            TryDelete(partial);
            throw;
        }
        ReceivedTransfer? finished = null;
        lock (gate)
        {
            current.Partial.Remove(partial);
            current.Saved[fileId] = target;
            if (current.Saved.Count == current.Files.Count && session == current)
            {
                session = null;
                finished = new ReceivedTransfer(current.From, current.Files.Keys.Select(id => current.Saved[id]).ToList(), null);
            }
        }
        if (finished != null) Received?.Invoke(finished);
        return HttpResponse.Empty;
    }

    /// <summary>Stops the transfer under way (the sender cancelled, or the person did): what's partly written goes.</summary>
    public void Cancel(string? sessionId = null)
    {
        Session? stopped;
        lock (gate)
        {
            if (session == null || sessionId != null && session.Id != sessionId) return;
            stopped = session;
            session = null;
        }
        foreach (var partial in stopped.Partial.ToList()) TryDelete(partial);
        Cancelled?.Invoke();
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    /// <summary>Where a received file goes: inside <paramref name="folder"/> whatever its name says ("../x" or "C:\x" can't leave
    /// it; a folder in it, like "photos/a.jpg", is kept), and not over a file already there ("a (1).jpg").</summary>
    internal static string Destination(string folder, string fileName)
    {
        var parts = fileName.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => string.Concat(part.Where(c => !Path.GetInvalidFileNameChars().Contains(c) && c != ':')).Trim())
            .Where(part => part.Length > 0 && part != "." && part != "..")
            .ToList();
        if (parts.Count == 0) parts.Add("file");
        var directory = Path.Combine(new[] { folder }.Concat(parts.SkipLast(1)).ToArray());
        Directory.CreateDirectory(directory);
        var name = parts[^1];
        var path = Path.Combine(directory, name);
        var stem = Path.GetFileNameWithoutExtension(name);
        var extension = Path.GetExtension(name);
        for (var copy = 1; File.Exists(path) || File.Exists(path + ".part"); copy++) path = Path.Combine(directory, $"{stem} ({copy}){extension}");
        return path;
    }
}
