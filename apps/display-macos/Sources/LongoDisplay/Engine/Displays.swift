import AppKit
import CoreGraphics

/// How a display's brightness is changed.
enum ControlMethod: String, Codable {
    /// Built-in and Apple displays, through DisplayServices.
    case native
    /// External monitors that answer DDC/CI over the cable.
    case ddc
    /// Anything else: gamma dimming only.
    case software
}

struct Display: Identifiable, Equatable {
    let id: CGDirectDisplayID
    /// Stable across reconnects and restarts (the display's UUID), used to keep its settings.
    let key: String
    let name: String
    let isBuiltin: Bool
    var method: ControlMethod
    var pixelSize: CGSize
    /// The monitor has a DDC channel, even if software dimming was chosen for it.
    var hasDDC = false
    /// False while turned off (see `DisplayPower`): connected, but macOS shows nothing on it.
    var isActive = true
}

/// What the user set for one display. Brightness, minimum and maximum are 0…1.
struct DisplaySettings: Codable, Equatable {
    var brightness = 0.7
    /// Sync mode maps the built-in display's 0…1 onto minimum…maximum.
    var minimum = 0.0
    var maximum = 1.0
    /// Extra software dimming on top of the hardware brightness, 0…0.8.
    var extraDim = 0.0
    /// Dim in software even though the monitor has DDC (some ports, like a MacBook's HDMI, don't pass it on).
    var softwareOnly = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplaySettings()
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? d.brightness
        minimum = try c.decodeIfPresent(Double.self, forKey: .minimum) ?? d.minimum
        maximum = try c.decodeIfPresent(Double.self, forKey: .maximum) ?? d.maximum
        extraDim = try c.decodeIfPresent(Double.self, forKey: .extraDim) ?? d.extraDim
        softwareOnly = try c.decodeIfPresent(Bool.self, forKey: .softwareOnly) ?? d.softwareOnly
    }
}

enum SyncMath {
    /// The external display's brightness when the built-in one is at `builtin`.
    static func map(builtin: Double, minimum: Double, maximum: Double) -> Double {
        let low = min(minimum, maximum), high = max(minimum, maximum)
        return low + min(max(builtin, 0), 1) * (high - low)
    }

    /// Brightness keys move in 16 steps, like macOS.
    static let keyStep = 1.0 / 16

    static func stepped(_ value: Double, up: Bool) -> Double {
        let steps = (value / keyStep).rounded()
        return min(max((steps + (up ? 1 : -1)) * keyStep, 0), 1)
    }
}

/// Keeps only the latest value while a slow write is in flight, so dragging a slider sends a handful of DDC
/// messages instead of hundreds, and the monitor always ends on the final value.
final class Coalescer<Value> {
    private let queue: DispatchQueue
    private let perform: (Value) -> Void
    private let lock = NSLock()
    private var pending: Value?
    private var busy = false

    init(label: String, perform: @escaping (Value) -> Void) {
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
        self.perform = perform
    }

    func submit(_ value: Value) {
        lock.lock()
        pending = value
        let start = !busy
        busy = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let value = pending else {
                busy = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            perform(value)
        }
    }
}

/// Finds displays and applies brightness to them with the right method.
@MainActor
final class DisplayEngine {
    private(set) var displays: [Display] = []
    private var channels: [CGDirectDisplayID: DDCChannel] = [:]
    private var writers: [CGDirectDisplayID: Coalescer<UInt16>] = [:]
    /// Each DDC display's maximum brightness value, read once (most monitors use 100).
    private var ddcMaximum: [CGDirectDisplayID: UInt16] = [:]
    private var dimmed: [CGDirectDisplayID: Double] = [:]
    /// Displays set to software dimming although they have DDC, by key.
    var softwareOnly: Set<String> = []
    /// A DDC display gave no valid answer when asked for its brightness (nil reading).
    var onDDCSilent: ((CGDirectDisplayID) -> Void)?
    /// Displays the app turned off, by key: they stay listed so they can be turned back on.
    var turnedOff: Set<String> = []
    var onChange: (() -> Void)?
    /// A DDC display's current brightness (0…1), once read from the monitor.
    var onDDCBrightness: ((CGDirectDisplayID, Double) -> Void)?

    init() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            let engine = Unmanaged<DisplayEngine>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { engine.scheduleRefresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private var refreshWork: DispatchWorkItem?

    /// Plugging a display in fires several callbacks; wait for them to settle.
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh()
            self?.onChange?()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func refresh() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        // A mirrored display shows the same picture as its source; list the source only.
        ids = ids.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }

        let external = ids.filter { CGDisplayIsBuiltin($0) == 0 && !DisplayServices.canChangeBrightness($0) }
        channels = DDCDiscovery.channels(for: external)
        writers = channels.mapValues { channel in
            Coalescer<UInt16>(label: "ddc") { value in channel.write(.brightness, value) }
        }
        for (id, channel) in channels where ddcMaximum[id] == nil {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let reading = channel.read(.brightness)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.ddcMaximum[id] = reading?.max ?? 100
                    if let reading {
                        self.onDDCBrightness?(id, Double(reading.current) / Double(reading.max))
                    } else {
                        self.onDDCSilent?(id)
                    }
                }
            }
        }

        let previous = displays
        var all = ids.map { id in
            let key = Self.key(for: id)
            let method: ControlMethod = DisplayServices.canChangeBrightness(id) ? .native
                : channels[id] != nil && !softwareOnly.contains(key) ? .ddc : .software
            return Display(id: id, key: key, name: Self.name(for: id),
                           isBuiltin: CGDisplayIsBuiltin(id) != 0, method: method,
                           pixelSize: CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id)),
                           hasDDC: channels[id] != nil)
        }
        // A turned-off display has no screen any more, so it keeps the name and method it had.
        for id in DisplayPower.inactiveOnline() {
            let key = Self.key(for: id)
            guard turnedOff.contains(key) else { continue }
            let known = previous.first { $0.key == key }
            all.append(Display(id: id, key: key, name: known?.name ?? Self.name(for: id), isBuiltin: CGDisplayIsBuiltin(id) != 0,
                               method: known?.method ?? .software, pixelSize: known?.pixelSize ?? .zero,
                               hasDDC: known?.hasDDC ?? false, isActive: false))
        }
        displays = all.sorted { ($0.isBuiltin ? 0 : 1, $0.name) < ($1.isBuiltin ? 0 : 1, $1.name) }
    }

    /// `--diagnose`: what the monitor answers when asked for its brightness over DDC (read only).
    func ddcReport(_ display: Display) -> String {
        guard let channel = channels[display.id] else { return "no DDC channel" }
        guard let reading = channel.read(.brightness) else { return "DDC: no answer" }
        return "DDC brightness \(reading.current)/\(reading.max)"
    }

    /// Turns a display off as if unplugged, or back on. Returns whether macOS accepted it.
    func setActive(_ display: Display, _ on: Bool) -> Bool {
        DisplayPower.set(display.id, on: on)
    }

    /// Turns back on the displays with these keys that are connected but off. Nothing else is touched.
    /// Returns whether none of them is still off.
    @discardableResult
    func turnOn(keys: Set<String>) -> Bool {
        for id in DisplayPower.inactiveOnline() where keys.contains(Self.key(for: id)) {
            // A display that's waking up can refuse once; ask again before giving up.
            if !DisplayPower.set(id, on: true) {
                usleep(300_000)
                DisplayPower.set(id, on: true)
            }
        }
        return !DisplayPower.inactiveOnline().contains { keys.contains(Self.key(for: $0)) }
    }

    /// The fallback when macOS won't turn a display off: a fully black picture. Gamma resets when the app quits.
    func setBlackout(_ display: Display, _ on: Bool) {
        setGamma(display.id, on ? 0 : 1)
    }

    /// Sets a display's brightness and extra dimming.
    func apply(_ settings: DisplaySettings, to display: Display) {
        switch display.method {
        case .native:
            DisplayServices.setBrightness(display.id, settings.brightness)
            setGamma(display.id, 1 - settings.extraDim)
        case .ddc:
            let max = Double(ddcMaximum[display.id] ?? 100)
            writers[display.id]?.submit(UInt16((settings.brightness * max).rounded()))
            setGamma(display.id, 1 - settings.extraDim)
        case .software:
            setGamma(display.id, (Gamma.floor + (1 - Gamma.floor) * settings.brightness) * (1 - settings.extraDim))
        }
    }

    func builtinBrightness() -> Double? {
        guard let builtin = displays.first(where: { $0.isBuiltin && $0.isActive }) else { return nil }
        return DisplayServices.brightness(builtin.id)
    }

    /// The current hardware brightness, to start from what the display shows.
    func currentBrightness(of display: Display) -> Double? {
        display.method == .native ? DisplayServices.brightness(display.id) : nil
    }

    func resetGamma() {
        dimmed.removeAll()
        Gamma.resetAll()
    }

    /// Gamma changes stack across displays, so undimming one restores everything and reapplies the rest.
    private func setGamma(_ id: CGDirectDisplayID, _ factor: Double) {
        if factor >= 0.999 {
            guard dimmed.removeValue(forKey: id) != nil else { return }
            Gamma.resetAll()
            for (other, value) in dimmed { Gamma.apply(other, factor: value) }
        } else {
            dimmed[id] = factor
            Gamma.apply(id, factor: factor)
        }
    }

    private static func key(for id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func name(for id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)")
    }
}
