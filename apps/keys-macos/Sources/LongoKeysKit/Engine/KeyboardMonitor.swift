import Foundation
import IOKit
import IOKit.hid

/// A connected keyboard, as reported by IOHID.
struct KeyboardDevice: Identifiable, Equatable {
    /// Stable across reconnects: vendor, product and serial (Bluetooth address) or USB location.
    let id: String
    var name: String
    var transport: String
    var vendorID: Int
    var productID: Int
    var locationID: Int
    var isBuiltIn: Bool

    var connection: String {
        if isBuiltIn { return "Built-in" }
        let t = transport.lowercased()
        if t.contains("bluetooth") { return "Bluetooth" }
        if t == "usb" { return "USB" }
        return transport.isEmpty ? "Wired" : transport
    }

    var symbol: String { isBuiltIn ? "laptopcomputer" : "keyboard" }
}

/// Watches keyboards coming and going, and which one is being typed on. Enumeration needs no permission;
/// seeing keystrokes needs Input Monitoring (without it `onActivity` just never fires).
final class KeyboardMonitor {
    var onChange: (([KeyboardDevice]) -> Void)?
    /// Called with a keyboard id whenever typing starts coming from a different keyboard.
    var onActivity: ((String) -> Void)?
    private var lastActive: String?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices: [UnsafeMutableRawPointer: KeyboardDevice] = [:]

    func start() {
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<KeyboardMonitor>.fromOpaque(context!).takeUnretainedValue().added(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<KeyboardMonitor>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
            Unmanaged<KeyboardMonitor>.fromOpaque(context!).takeUnretainedValue().activity(device)
        }, context)
        // Common modes, so devices keep reporting while any alert or panel in the app runs its modal loop.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Opens the devices again, so keystrokes start arriving once Input Monitoring has been granted.
    func reopen() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func activity(_ device: IOHIDDevice) {
        guard let id = devices[Self.key(device)]?.id, id != lastActive else { return }
        lastActive = id
        onActivity?(id)
    }

    /// The keyboards connected right now, without watching (for `--diagnose`).
    func snapshot() -> [KeyboardDevice] {
        let matching: [String: Any] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        for element in set as NSSet { added(element as! IOHIDDevice, notify: false) }
        return unique()
    }

    private func added(_ device: IOHIDDevice, notify: Bool = true) {
        guard let info = Self.describe(device) else { return }
        devices[Self.key(device)] = info
        if notify { onChange?(unique()) }
    }

    private func removed(_ device: IOHIDDevice) {
        devices.removeValue(forKey: Self.key(device))
        onChange?(unique())
    }

    /// One keyboard often exposes several HID interfaces; keep one entry per id. Built-in first.
    private func unique() -> [KeyboardDevice] {
        var seen: [String: KeyboardDevice] = [:]
        for device in devices.values where seen[device.id] == nil { seen[device.id] = device }
        return seen.values.sorted { ($0.isBuiltIn ? 0 : 1, $0.name) < ($1.isBuiltIn ? 0 : 1, $1.name) }
    }

    private static func key(_ device: IOHIDDevice) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(device).toOpaque()
    }

    static func describe(_ device: IOHIDDevice) -> KeyboardDevice? {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
        let name = (property(kIOHIDProductKey) as? String ?? "").trimmingCharacters(in: .whitespaces)
        let builtIn = property(kIOHIDBuiltInKey) as? Bool == true
        // Many mice (and their receivers) also present a keyboard interface for their extra buttons. The MacBook's
        // own "Keyboard / Trackpad" is a pointer too, but it is a keyboard first.
        let lower = name.lowercased()
        if !builtIn && !lower.contains("keyboard") {
            if ["mouse", "trackball", "receiver"].contains(where: lower.contains) { return nil }
            if IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) { return nil }
        }

        let vendor = property(kIOHIDVendorIDKey) as? Int ?? 0
        let product = property(kIOHIDProductIDKey) as? Int ?? 0
        let location = property(kIOHIDLocationIDKey) as? Int ?? 0
        let serial = (property(kIOHIDSerialNumberKey) as? String).flatMap { $0.isEmpty ? nil : $0 }
        return KeyboardDevice(
            id: "\(vendor):\(product):\(serial ?? String(location))",
            name: builtIn ? "Built-in Keyboard" : (name.isEmpty ? "Keyboard" : name),
            transport: property(kIOHIDTransportKey) as? String ?? "",
            vendorID: vendor, productID: product, locationID: location, isBuiltIn: builtIn)
    }
}
