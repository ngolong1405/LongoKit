using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace LongoShare;

/// <summary>
/// Finding devices as LocalSend does: an announcement to the multicast group 224.0.0.167:53317 on every network, answered
/// with /register (or, failing that, a multicast answer). Where a router drops multicast, every address of the local
/// networks is asked instead (Scan).
/// </summary>
public sealed class Discovery : IDisposable
{
    private readonly Func<DeviceInfo> self;
    private readonly Func<string, int, string, Task<Peer?>> register;
    private readonly int multicastPort;
    private readonly IPAddress group = IPAddress.Parse(Protocol.MulticastAddress);
    private readonly CancellationTokenSource stop = new();
    private Socket? socket;

    /// <summary>A device announced itself or answered.</summary>
    public event Action<Peer>? Found;

    public Discovery(Func<DeviceInfo> self, Func<string, int, string, Task<Peer?>> register, int multicastPort = Protocol.Port)
    {
        this.self = self;
        this.register = register;
        this.multicastPort = multicastPort;
    }

    /// <summary>This PC's IPv4 addresses on networks that are up (not loopback, not link-local).</summary>
    public static IReadOnlyList<IPAddress> LocalAddresses() => NetworkInterface.GetAllNetworkInterfaces()
        .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback && n.SupportsMulticast)
        .SelectMany(n => n.GetIPProperties().UnicastAddresses)
        .Select(a => a.Address)
        .Where(a => a.AddressFamily == AddressFamily.InterNetwork && !a.ToString().StartsWith("169.254.", StringComparison.Ordinal))
        .Distinct()
        .ToList();

    public void Start()
    {
        try
        {
            socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            socket.Bind(new IPEndPoint(IPAddress.Any, multicastPort));
            var joined = false;
            foreach (var local in LocalAddresses())
            {
                try
                {
                    socket.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.AddMembership, new MulticastOption(group, local));
                    joined = true;
                }
                catch (SocketException) { }
            }
            if (!joined) socket.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.AddMembership, new MulticastOption(group));
            _ = Listen(socket);
        }
        catch (SocketException)
        {
            // No multicast here (the port taken, no network): Scan still finds devices.
            socket?.Dispose();
            socket = null;
        }
    }

    private async Task Listen(Socket listening)
    {
        var buffer = new byte[8192];
        while (!stop.IsCancellationRequested)
        {
            SocketReceiveFromResult received;
            try
            {
                received = await listening.ReceiveFromAsync(buffer, SocketFlags.None, new IPEndPoint(IPAddress.Any, 0), stop.Token);
            }
            catch (Exception) when (!stop.IsCancellationRequested)
            {
                continue;
            }
            catch (Exception)
            {
                return;
            }
            DeviceInfo? info;
            try
            {
                info = JsonSerializer.Deserialize<DeviceInfo>(buffer.AsSpan(0, received.ReceivedBytes), Protocol.Json);
            }
            catch (JsonException)
            {
                continue;
            }
            var me = self();
            if (info == null || info.Fingerprint == me.Fingerprint) continue;
            var address = ((IPEndPoint)received.RemoteEndPoint).Address.ToString();
            Found?.Invoke(new Peer(info with { Announce = null }, address));
            if (info.Announce == true) _ = Answer(info, address);
        }
    }

    /// <summary>Answers an announcement: /register on the device, or a multicast answer if that doesn't get through.</summary>
    private async Task Answer(DeviceInfo info, string address)
    {
        if (await register(address, info.Port, info.Protocol) is { } peer)
        {
            Found?.Invoke(peer);
            return;
        }
        Send(self() with { Announce = false });
    }

    /// <summary>Says this device is here, asking the others to answer.</summary>
    public void Announce() => Send(self() with { Announce = true });

    private void Send(DeviceInfo info)
    {
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(info, Protocol.Json));
        var target = new IPEndPoint(group, multicastPort);
        foreach (var local in LocalAddresses())
        {
            try
            {
                using var sending = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                sending.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, local.GetAddressBytes());
                sending.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 1);
                sending.SendTo(bytes, target);
            }
            catch (SocketException) { }
        }
    }

    /// <summary>Asks every address of the local networks (/24 around each of this PC's addresses), 64 at a time.</summary>
    public async Task Scan(int port, string protocol, CancellationToken token = default)
    {
        var own = LocalAddresses();
        var targets = own.SelectMany(address =>
        {
            var bytes = address.GetAddressBytes();
            return Enumerable.Range(1, 254).Select(last => new IPAddress(new[] { bytes[0], bytes[1], bytes[2], (byte)last }));
        }).Where(a => !own.Contains(a)).Distinct().ToList();
        using var gate = new SemaphoreSlim(64);
        await Task.WhenAll(targets.Select(async target =>
        {
            await gate.WaitAsync(token);
            try
            {
                if (await register(target.ToString(), port, protocol) is { } peer) Found?.Invoke(peer);
            }
            finally
            {
                gate.Release();
            }
        }));
    }

    public void Dispose()
    {
        stop.Cancel();
        socket?.Dispose();
    }
}
