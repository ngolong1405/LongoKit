import Foundation
import IOKit.hidsystem

/// Gives keyboards their key → key table through `UserKeyMapping`, the same mechanism as `hidutil`: no permission
/// needed, works in password fields, nothing installed. macOS forgets the table when a keyboard reconnects or
/// the Mac restarts, so the app applies it again whenever keyboards change.
enum KeyMapper {
    private static let property = "UserKeyMapping" as CFString

    /// The array `UserKeyMapping` takes. Sorted so the same table always produces the same array.
    static func mappingArray(_ table: [Key: Key]) -> [[String: UInt64]] {
        table.sorted { $0.key.usage < $1.key.usage }.map {
            ["HIDKeyboardModifierMappingSrc": $0.key.mappingValue, "HIDKeyboardModifierMappingDst": $0.value.mappingValue]
        }
    }

    /// Sets each keyboard's table; an empty table restores the keyboard. Returns how many keyboards took it.
    ///
    /// Goes through `hidutil`: a table set from this app's own HID client is stored on the keyboard (and reads back)
    /// but macOS doesn't use it for typing, while the same table set by `hidutil` takes effect right away.
    @discardableResult
    static func apply(_ tables: [(KeyboardDevice, [Key: Key])]) -> Int {
        tables.filter { keyboard, table in
            let matching: [String: Any] = [
                kIOHIDVendorIDKey: keyboard.vendorID,
                kIOHIDProductIDKey: keyboard.productID,
                kIOHIDLocationIDKey: UInt32(truncatingIfNeeded: keyboard.locationID),
            ]
            return hidutil(matching: matching, table: mappingArray(table))
        }.count
    }

    /// Whether some keyboard service doesn't have the table it should. macOS drops a keyboard's table when it
    /// reconnects or wakes (Bluetooth keyboards do this on their own), sometimes after the app last applied it.
    static func isOutOfDate(_ tables: [(KeyboardDevice, [Key: Key])]) -> Bool {
        let services = keyboardServices()
        for (keyboard, table) in tables {
            let expected = mappingArray(table)
            for service in services where matches(service, keyboard) {
                let current = IOHIDServiceClientCopyProperty(service, property) as? [[String: Any]] ?? []
                let pairs = current.compactMap { entry -> [String: UInt64]? in
                    guard let src = (entry["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
                          let dst = (entry["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value else { return nil }
                    return ["HIDKeyboardModifierMappingSrc": src, "HIDKeyboardModifierMappingDst": dst]
                }
                let sorted = pairs.sorted { ($0["HIDKeyboardModifierMappingSrc"] ?? 0) < ($1["HIDKeyboardModifierMappingSrc"] ?? 0) }
                if sorted != expected { return true }
            }
        }
        return false
    }

    /// Every keyboard back to normal.
    static func clearAll() {
        hidutil(matching: [kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop, kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard],
                table: [])
    }

    /// `hidutil property --matching … --set '{"UserKeyMapping": …}'`. True when it ran fine.
    @discardableResult
    private static func hidutil(matching: [String: Any], table: [[String: UInt64]]) -> Bool {
        guard let match = try? JSONSerialization.data(withJSONObject: matching),
              let set = try? JSONSerialization.data(withJSONObject: [property as String: table]) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--matching", String(decoding: match, as: UTF8.self),
                             "--set", String(decoding: set, as: UTF8.self)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// `--diagnose`: the table each keyboard service has now.
    static func current() -> [(name: String, count: Int)] {
        keyboardServices().map { service in
            let name = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String ?? "?"
            let table = IOHIDServiceClientCopyProperty(service, property) as? [Any] ?? []
            return (name, table.count)
        }
    }

    /// One client for the app's lifetime: the services it hands out stop working once their client goes away.
    private static let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    private static func keyboardServices() -> [IOHIDServiceClient] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.filter { IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 }
    }

    private static func matches(_ service: IOHIDServiceClient, _ keyboard: KeyboardDevice) -> Bool {
        func number(_ key: String) -> Int? { (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue }
        return number(kIOHIDVendorIDKey) == keyboard.vendorID && number(kIOHIDProductIDKey) == keyboard.productID
            && (number(kIOHIDLocationIDKey) ?? keyboard.locationID) == keyboard.locationID
    }
}
