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

    /// Sets each keyboard's table; an empty table restores the keyboard. Returns how many services took it.
    @discardableResult
    static func apply(_ tables: [(KeyboardDevice, [Key: Key])]) -> Int {
        let services = keyboardServices()
        var applied = 0
        for (keyboard, table) in tables {
            let array = mappingArray(table) as CFArray
            for service in services where matches(service, keyboard) {
                if IOHIDServiceClientSetProperty(service, property, array) { applied += 1 }
            }
        }
        return applied
    }

    /// Every keyboard back to normal.
    static func clearAll() {
        for service in keyboardServices() {
            IOHIDServiceClientSetProperty(service, property, [] as CFArray)
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
