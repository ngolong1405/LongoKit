import CoreGraphics
import Foundation
import IOKit

// DDC/CI over the display cable on Apple Silicon, the same route MonitorControl and Lunar use: each external
// display's DCPAVServiceProxy in the IORegistry exposes an IOAVService that can send I²C messages to the
// monitor's controller (chip address 0x37, register 0x51). These functions are exported by IOKit but not
// declared in its headers.
//
// A MacBook Pro's HDMI port goes through a DisplayPort-to-HDMI converter (MCDP29XX) that only passes DDC on at
// chip address 0xB7, as m1ddc found; at 0x37 the monitor never hears it.

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
                                _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32,
                                 _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn

/// VESA MCCS control codes used here.
enum VCP: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
}

/// One external display's DDC channel. Calls block for tens of milliseconds, so use it off the main thread.
/// It holds no mutable state; the IOAVService calls are safe to make from background queues.
final class DDCChannel: @unchecked Sendable {
    private let service: CFTypeRef
    let chipAddress: UInt32
    private static let dataAddress: UInt32 = 0x51
    static let standardChip: UInt32 = 0x37
    static let mcdpChip: UInt32 = 0xB7

    fileprivate init(service: CFTypeRef, chipAddress: UInt32) {
        self.service = service
        self.chipAddress = chipAddress
    }

    /// Sets a control. Monitors miss messages now and then, so it's sent twice, as MonitorControl does.
    @discardableResult
    func write(_ code: VCP, _ value: UInt16) -> Bool {
        var packet = Self.writePacket(code.rawValue, value)
        var ok = false
        for _ in 0..<2 {
            usleep(10_000)
            ok = IOAVServiceWriteI2C(service, chipAddress, Self.dataAddress, &packet, UInt32(packet.count)) == KERN_SUCCESS || ok
        }
        return ok
    }

    /// Current and maximum value of a control, or nil when the monitor doesn't answer.
    func read(_ code: VCP) -> (current: UInt16, max: UInt16)? {
        var request = Self.readPacket(code.rawValue)
        for _ in 0..<3 {
            usleep(10_000)
            guard IOAVServiceWriteI2C(service, chipAddress, Self.dataAddress, &request, UInt32(request.count)) == KERN_SUCCESS else {
                continue
            }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard IOAVServiceReadI2C(service, chipAddress, Self.dataAddress, &reply, UInt32(reply.count)) == KERN_SUCCESS,
                  let parsed = Self.parseReply(reply, code: code.rawValue) else { continue }
            return parsed
        }
        return nil
    }

    // MARK: Packets (internal for the self-test)

    /// Set VCP Feature: length, opcode 0x03, code, value high, value low, checksum.
    static func writePacket(_ code: UInt8, _ value: UInt16) -> [UInt8] {
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        packet.append(checksum(seed: 0x6E ^ 0x51, packet))
        return packet
    }

    /// Get VCP Feature: length, opcode 0x01, code, checksum. Like a write, the checksum covers the destination
    /// (0x6E) and source (0x51) addresses; most monitors forgive leaving 0x51 out, the HDMI converter doesn't.
    static func readPacket(_ code: UInt8) -> [UInt8] {
        var packet: [UInt8] = [0x82, 0x01, code]
        packet.append(checksum(seed: 0x6E ^ 0x51, packet))
        return packet
    }

    /// VCP Feature Reply: source, length, 0x02, result, code, type, max hi, max lo, current hi, current lo, checksum.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 10, reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return max > 0 ? (current, max) : nil
    }

    static func checksum(seed: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed, ^)
    }
}

/// Finds the DDC channel for each external display.
enum DDCDiscovery {
    /// What the IORegistry says about a framebuffer, to tell monitors apart.
    private struct Candidate {
        var vendor: UInt32?
        var model: UInt32?
        var serial: UInt32?
        var name: String?
        var service: CFTypeRef
        var chipAddress: UInt32
    }

    /// The proxy sits behind the HDMI port's MCDP29XX converter.
    private static func isMCDP29XX(_ proxy: io_registry_entry_t) -> Bool {
        var parent = io_registry_entry_t()
        guard IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        let provider = IORegistryEntryCreateCFProperty(parent, "EPICProviderClass" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        return provider == "AppleDCPMCDP29XX"
    }

    /// Walks the registry in order: each external DCPAVServiceProxy follows the framebuffer it drives,
    /// so the most recent framebuffer's product attributes describe it.
    private static func candidates() -> [Candidate] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively),
                                       &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [Candidate] = []
        var attributes: [String: Any] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuffer)
            let name = String(cString: nameBuffer)

            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                let display = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
                attributes = display?["ProductAttributes"] as? [String: Any] ?? [:]
            } else if name == "DCPAVServiceProxy" {
                let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                guard location == "External",
                      let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
                found.append(Candidate(
                    vendor: (attributes["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                    model: (attributes["ProductID"] as? NSNumber)?.uint32Value,
                    serial: (attributes["SerialNumber"] as? NSNumber)?.uint32Value,
                    name: attributes["ProductName"] as? String,
                    service: service,
                    chipAddress: isMCDP29XX(entry) ? DDCChannel.mcdpChip : DDCChannel.standardChip))
            }
        }
        return found
    }

    /// DDC channels for the given external displays. A display without a confident match gets none and falls
    /// back to software dimming.
    static func channels(for displays: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCChannel] {
        #if arch(arm64)
        var pool = candidates()
        var result: [CGDirectDisplayID: DDCChannel] = [:]
        for display in displays {
            let vendor = CGDisplayVendorNumber(display)
            let model = CGDisplayModelNumber(display)
            let serial = CGDisplaySerialNumber(display)
            let scored = pool.enumerated().map { index, candidate -> (Int, Int) in
                var score = 0
                if candidate.vendor == vendor { score += 1 }
                if candidate.model == model { score += 1 }
                if serial != 0, candidate.serial == serial { score += 2 }
                return (index, score)
            }
            // Vendor and model must match, unless there's exactly one external display and one channel.
            let best = scored.max { $0.1 < $1.1 }
            if let best, best.1 >= 2 || (displays.count == 1 && pool.count == 1) {
                result[display] = DDCChannel(service: pool[best.0].service, chipAddress: pool[best.0].chipAddress)
                pool.remove(at: best.0)
            }
        }
        return result
        #else
        // Intel Macs reach DDC through IOFramebuffer instead; not supported yet, so they use software dimming.
        return [:]
        #endif
    }
}
