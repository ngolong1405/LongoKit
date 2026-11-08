import Foundation
import IOKit
import IOKit.hid

/// A connected pointing device, as reported by IOHID.
struct MouseDevice: Identifiable, Equatable {
    /// Stable across reconnects: vendor, product and serial (Bluetooth address) or USB location.
    let id: String
    var product: String
    var manufacturer: String
    var transport: String
    var vendorID: Int
    var productID: Int
    var battery: Int?

    var connection: String {
        let t = transport.lowercased()
        if t.contains("bluetooth") { return "Bluetooth" }
        if t == "usb" { return product.lowercased().contains("receiver") ? "USB Receiver" : "USB" }
        return transport.isEmpty ? "Wired" : transport
    }

    var hardwareID: String { String(format: "%04X:%04X", vendorID, productID) }

    var symbol: String { MouseDevice.symbol(for: product) }

    static func symbol(for product: String) -> String {
        let name = product.lowercased()
        if name.contains("magic mouse") { return "hand.point.up.left" }
        if ["razer", "gaming", "g pro", "g502", "steelseries", "deathadder", "viper"].contains(where: name.contains) {
            return "gamecontroller"
        }
        return "computermouse"
    }
}

/// Watches mice coming and going, and which one the user is touching right now.
/// Input values need Input Monitoring; enumeration works without it.
final class DeviceMonitor {
    var onChange: (([MouseDevice]) -> Void)?
    /// Called with a device id whenever input starts coming from a different mouse.
    var onActivity: ((String) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices: [UnsafeMutableRawPointer: MouseDevice] = [:]
    private var lastActive: String?

    func start() {
        let matching: [[String: Any]] = [[
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue().added(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
            Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue().activity(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Re-reads properties such as battery level for every attached device.
    func refresh() {
        guard let set = IOHIDManagerCopyDevices(manager) else { return }
        devices.removeAll()
        // CFSet doesn't bridge to Set<IOHIDDevice>; walk it as an NSSet of CF objects.
        for element in set as NSSet {
            added(element as! IOHIDDevice, notify: false)
        }
        publish()
    }

    private func added(_ device: IOHIDDevice, notify: Bool = true) {
        guard let info = Self.describe(device) else { return }
        devices[Self.key(device)] = info
        if notify { publish() }
    }

    private func removed(_ device: IOHIDDevice) {
        devices.removeValue(forKey: Self.key(device))
        publish()
    }

    private func activity(_ device: IOHIDDevice) {
        guard let id = devices[Self.key(device)]?.id, id != lastActive else { return }
        lastActive = id
        onActivity?(id)
    }

    private func publish() {
        // One physical mouse often exposes several HID interfaces; keep one entry per id.
        var unique: [String: MouseDevice] = [:]
        for device in devices.values where unique[device.id] == nil { unique[device.id] = device }
        onChange?(unique.values.sorted { $0.product < $1.product })
    }

    private static func key(_ device: IOHIDDevice) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(device).toOpaque()
    }

    private static func describe(_ device: IOHIDDevice) -> MouseDevice? {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }

        let product = (property(kIOHIDProductKey) as? String ?? "").trimmingCharacters(in: .whitespaces)
        // Built-in and Magic trackpads report a mouse usage too, but are never remapped.
        if property(kIOHIDBuiltInKey) as? Bool == true || product.lowercased().contains("trackpad") { return nil }

        let vendor = property(kIOHIDVendorIDKey) as? Int ?? 0
        let productID = property(kIOHIDProductIDKey) as? Int ?? 0
        let serial = (property(kIOHIDSerialNumberKey) as? String).flatMap { $0.isEmpty ? nil : $0 }
        let location = property(kIOHIDLocationIDKey) as? Int ?? 0

        return MouseDevice(
            id: "\(vendor):\(productID):\(serial ?? String(location))",
            product: product.isEmpty ? "Mouse" : product,
            manufacturer: property(kIOHIDManufacturerKey) as? String ?? "",
            transport: property(kIOHIDTransportKey) as? String ?? "",
            vendorID: vendor,
            productID: productID,
            battery: battery(of: device))
    }

    /// Apple and many Bluetooth mice publish BatteryPercent somewhere up their IORegistry chain.
    private static func battery(of device: IOHIDDevice) -> Int? {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "BatteryPercent" as CFString,
                                                    kCFAllocatorDefault, options)
        return value as? Int
    }
}
