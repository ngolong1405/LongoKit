using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace LongoShare;

/// <summary>A request: its method, path, query, headers, body (to read once) and where it came from.</summary>
public sealed class HttpRequest
{
    public string Method { get; init; } = "";
    public string Path { get; init; } = "";
    public Dictionary<string, string> Query { get; init; } = new();
    public Dictionary<string, string> Headers { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public Stream Body { get; init; } = Stream.Null;
    public IPAddress Remote { get; init; } = IPAddress.None;

    public string? this[string query] => Query.TryGetValue(query, out var value) ? value : null;
}

/// <summary>An answer: a status, and JSON or nothing.</summary>
public sealed record HttpResponse(int Status, string? Json = null)
{
    public static HttpResponse Ok(object value) => new(200, System.Text.Json.JsonSerializer.Serialize(value, Protocol.Json));
    public static readonly HttpResponse Empty = new(200);
}

/// <summary>
/// The smallest HTTP/1.1 server that LocalSend needs, over TLS or not: requests with a JSON or binary body (by
/// Content-Length or chunked), kept-alive connections, one task per connection. No web framework: the app stays light.
/// </summary>
public sealed class HttpServer : IDisposable
{
    private readonly TcpListener listener;
    private readonly X509Certificate2? certificate;
    private readonly Func<HttpRequest, Task<HttpResponse>> handle;
    private readonly CancellationTokenSource stop = new();

    public int Port => ((IPEndPoint)listener.LocalEndpoint).Port;

    /// <param name="port">0 picks a free one (tests).</param>
    public HttpServer(int port, X509Certificate2? certificate, Func<HttpRequest, Task<HttpResponse>> handle)
    {
        this.certificate = certificate;
        this.handle = handle;
        listener = new TcpListener(IPAddress.IPv6Any, port);
        listener.Server.DualMode = true;
    }

    public void Start()
    {
        listener.Start();
        _ = AcceptLoop();
    }

    private async Task AcceptLoop()
    {
        while (!stop.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await listener.AcceptTcpClientAsync(stop.Token);
            }
            catch (Exception) when (stop.IsCancellationRequested)
            {
                return;
            }
            catch (SocketException)
            {
                continue;
            }
            _ = Serve(client);
        }
    }

    private async Task Serve(TcpClient client)
    {
        using var _ = client;
        client.NoDelay = true;
        var remote = ((IPEndPoint)client.Client.RemoteEndPoint!).Address;
        if (remote.IsIPv4MappedToIPv6) remote = remote.MapToIPv4();
        try
        {
            Stream stream = client.GetStream();
            if (certificate != null)
            {
                var tls = new SslStream(stream, false);
                await tls.AuthenticateAsServerAsync(new SslServerAuthenticationOptions { ServerCertificate = certificate }, stop.Token);
                stream = tls;
            }
            await using var connection = stream;
            var reader = new BufferedReader(connection);
            while (!stop.IsCancellationRequested)
            {
                var head = await reader.ReadHead(stop.Token);
                if (head == null) return;
                var request = Parse(head, reader, remote);
                HttpResponse response;
                try
                {
                    response = await handle(request);
                }
                catch (Exception)
                {
                    response = new HttpResponse(500);
                }
                // What the handler didn't read is skipped, so the next request starts where it should.
                await request.Body.CopyToAsync(Stream.Null, stop.Token);
                var keepAlive = !string.Equals(request.Headers.GetValueOrDefault("Connection"), "close", StringComparison.OrdinalIgnoreCase);
                await Write(connection, response, keepAlive);
                if (!keepAlive) return;
            }
        }
        catch (Exception)
        {
            // A connection that broke off, or a handshake that failed: nothing to do but close it.
        }
    }

    private static HttpRequest Parse(string head, BufferedReader reader, IPAddress remote)
    {
        var lines = head.Split("\r\n");
        var first = lines[0].Split(' ');
        var target = first.Length > 1 ? first[1] : "/";
        var question = target.IndexOf('?');
        var path = question < 0 ? target : target[..question];
        var query = new Dictionary<string, string>();
        if (question >= 0)
        {
            foreach (var pair in target[(question + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var equals = pair.IndexOf('=');
                var key = Uri.UnescapeDataString(equals < 0 ? pair : pair[..equals]);
                query[key] = equals < 0 ? "" : Uri.UnescapeDataString(pair[(equals + 1)..].Replace('+', ' '));
            }
        }
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon > 0) headers[line[..colon].Trim()] = line[(colon + 1)..].Trim();
        }
        Stream body = headers.TryGetValue("Transfer-Encoding", out var encoding) && encoding.Contains("chunked", StringComparison.OrdinalIgnoreCase)
            ? new ChunkedStream(reader)
            : new LengthStream(reader, headers.TryGetValue("Content-Length", out var length) && long.TryParse(length, out var count) ? count : 0);
        return new HttpRequest { Method = first[0], Path = path, Query = query, Headers = headers, Body = body, Remote = remote };
    }

    private static async Task Write(Stream stream, HttpResponse response, bool keepAlive)
    {
        var body = response.Json == null ? Array.Empty<byte>() : Encoding.UTF8.GetBytes(response.Json);
        var head = $"HTTP/1.1 {response.Status} {Reason(response.Status)}\r\n" +
                   (response.Json != null ? "Content-Type: application/json; charset=utf-8\r\n" : "") +
                   $"Content-Length: {body.Length}\r\nConnection: {(keepAlive ? "keep-alive" : "close")}\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head));
        if (body.Length > 0) await stream.WriteAsync(body);
        await stream.FlushAsync();
    }

    private static string Reason(int status) => status switch
    {
        200 => "OK", 204 => "No Content", 400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
        409 => "Conflict", 422 => "Unprocessable Entity", 429 => "Too Many Requests", _ => "Internal Server Error",
    };

    public void Dispose()
    {
        stop.Cancel();
        listener.Stop();
    }

    /// <summary>Reads the head of a request byte by byte from a buffer, leaving the body in the buffer for the body streams.</summary>
    internal sealed class BufferedReader
    {
        private readonly Stream stream;
        private readonly byte[] buffer = new byte[64 * 1024];
        private int start, end;

        public BufferedReader(Stream stream) => this.stream = stream;

        public async Task<string?> ReadHead(CancellationToken token)
        {
            var head = new StringBuilder();
            while (true)
            {
                if (start == end && !await Fill(token)) return head.Length == 0 ? null : throw new EndOfStreamException();
                var b = buffer[start++];
                head.Append((char)b);
                if (head.Length >= 4 && head[^1] == '\n' && head[^2] == '\r' && head[^3] == '\n' && head[^4] == '\r')
                    return head.ToString(0, head.Length - 4);
                if (head.Length > 64 * 1024) throw new InvalidDataException("Header too large");
            }
        }

        public async Task<string> ReadLine(CancellationToken token)
        {
            var line = new StringBuilder();
            while (true)
            {
                if (start == end && !await Fill(token)) throw new EndOfStreamException();
                var b = buffer[start++];
                if (b == '\n') return line.ToString().TrimEnd('\r');
                line.Append((char)b);
            }
        }

        public async Task<int> Read(Memory<byte> into, CancellationToken token)
        {
            if (start == end && !await Fill(token)) return 0;
            var count = Math.Min(into.Length, end - start);
            buffer.AsMemory(start, count).CopyTo(into);
            start += count;
            return count;
        }

        private async Task<bool> Fill(CancellationToken token)
        {
            start = 0;
            end = await stream.ReadAsync(buffer, token);
            return end > 0;
        }
    }

    /// <summary>A body of a known length.</summary>
    private sealed class LengthStream : Stream
    {
        private readonly BufferedReader reader;
        private long left;

        public LengthStream(BufferedReader reader, long length)
        {
            this.reader = reader;
            left = length;
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default)
        {
            if (left <= 0) return 0;
            var read = await reader.Read(buffer[..(int)Math.Min(buffer.Length, left)], token);
            if (read == 0) throw new EndOfStreamException();
            left -= read;
            return read;
        }

        public override int Read(byte[] buffer, int offset, int count) => ReadAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    /// <summary>A chunked body ("Transfer-Encoding: chunked").</summary>
    private sealed class ChunkedStream : Stream
    {
        private readonly BufferedReader reader;
        private long chunk;
        private bool done;

        public ChunkedStream(BufferedReader reader) => this.reader = reader;

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default)
        {
            if (done) return 0;
            if (chunk == 0)
            {
                var size = await reader.ReadLine(token);
                chunk = Convert.ToInt64(size.Split(';')[0].Trim(), 16);
                if (chunk == 0)
                {
                    // The trailer, up to its blank line.
                    while ((await reader.ReadLine(token)).Length > 0) { }
                    done = true;
                    return 0;
                }
            }
            var read = await reader.Read(buffer[..(int)Math.Min(buffer.Length, chunk)], token);
            if (read == 0) throw new EndOfStreamException();
            chunk -= read;
            if (chunk == 0) await reader.ReadLine(token);
            return read;
        }

        public override int Read(byte[] buffer, int offset, int count) => ReadAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
