import Darwin
import Foundation

/// Finding devices as LocalSend does: an announcement to the multicast group, answered by each device over HTTP
/// (/register) or, failing that, by multicast. When a network drops multicast, `scan` asks every address on it.
final class Discovery: @unchecked Sendable {
    private let me: @Sendable () -> DeviceInfo
    private let register: @Sendable (String, Int, String) async -> Peer?
    private var socket: Int32 = -1
    private var reader: Thread?

    /// A device heard from.
    var found: @Sendable (Peer) -> Void = { _ in }

    init(me: @escaping @Sendable () -> DeviceInfo, register: @escaping @Sendable (String, Int, String) async -> Peer?) {
        self.me = me
        self.register = register
    }

    /// This Mac's IPv4 addresses on its networks (Wi-Fi, Ethernet), with their interfaces.
    static func localAddresses() -> [(address: in_addr, mask: in_addr, name: String)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [(in_addr, in_addr, String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), let mask = entry.ifa_netmask,
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            // Tunnels (VPN) and Apple's peer-to-peer links aren't the local network.
            if name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            // Link-local (169.254.x.x): no network.
            if UInt32(bigEndian: ip.s_addr) >> 16 == 0xA9FE { continue }
            result.append((ip, netmask, name))
        }
        return result
    }

    static func text(_ address: in_addr) -> String {
        var copy = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &copy, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }

    func start() {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(ShareProtocol.port).bigEndian)
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(fd)
            return
        }
        for local in Self.localAddresses() {
            var membership = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(ShareProtocol.multicastAddress)), imr_interface: local.address)
            setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size))
        }
        var loop: UInt8 = 0
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
        socket = fd
        let thread = Thread { [weak self] in self?.listen(fd) }
        thread.name = "LongoShare.discovery"
        thread.qualityOfService = .utility
        reader = thread
        thread.start()
    }

    private func listen(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            if count <= 0 { return }
            guard let info = try? ShareProtocol.decoder.decode(DeviceInfo.self, from: Data(buffer[0..<count])) else { continue }
            let mine = me()
            if info.fingerprint == mine.fingerprint { continue }
            let peer = Peer(info: info, address: Self.text(from.sin_addr))
            found(peer)
            if info.announce == true {
                // Answer over HTTP; a device that can't be reached that way hears a multicast answer instead.
                Task {
                    if await self.register(peer.address, info.port, info.protocol) == nil { self.send(announce: false) }
                }
            }
        }
    }

    /// Tells the group this device is here; others answer.
    func announce() {
        send(announce: true)
    }

    private func send(announce: Bool) {
        guard socket >= 0 else { return }
        var info = me()
        info.announce = announce
        guard let data = try? ShareProtocol.encoder.encode(info) else { return }
        var group = sockaddr_in()
        group.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = in_port_t(UInt16(ShareProtocol.port).bigEndian)
        group.sin_addr = in_addr(s_addr: inet_addr(ShareProtocol.multicastAddress))
        // Out of every network, not just the default one.
        for local in Self.localAddresses() {
            var interface = local.address
            setsockopt(socket, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size))
            _ = data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &group) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(socket, bytes.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    /// Asks every address of the local networks (a /24 around this Mac's address), 64 at a time: HTTPS first (as
    /// LocalSend has it), then HTTP where something answered at once but not over HTTPS.
    func scan(port: Int) async {
        var targets: [String] = []
        for local in Self.localAddresses() {
            let ip = UInt32(bigEndian: local.address.s_addr)
            let network = ip & 0xFFFF_FF00
            for host in UInt32(1)...254 where network | host != ip {
                targets.append(Self.text(in_addr(s_addr: (network | host).bigEndian)))
            }
        }
        await withTaskGroup(of: Peer?.self) { group in
            var next = targets.makeIterator()
            for _ in 0..<64 {
                guard let target = next.next() else { break }
                group.addTask { await self.ask(target, port) }
            }
            while let result = await group.next() {
                if let result { found(result) }
                if let target = next.next() { group.addTask { await self.ask(target, port) } }
            }
        }
    }

    private func ask(_ address: String, _ port: Int) async -> Peer? {
        let start = Date()
        if let peer = await register(address, port, "https") { return peer }
        // Nothing there waits out the timeout; a device on plain HTTP fails the TLS handshake at once.
        return Date().timeIntervalSince(start) < 1 ? await register(address, port, "http") : nil
    }

    func stop() {
        if socket >= 0 {
            // Shutting it down ends the reader's recvfrom.
            shutdown(socket, SHUT_RDWR)
            close(socket)
            socket = -1
        }
    }
}
