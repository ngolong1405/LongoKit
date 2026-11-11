import AppKit
import CoreGraphics
import LongoKitUI

/// Modifier keys we care about, stored as raw `CGEventFlags` bits.
struct Modifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt64

    static let command = Modifiers(rawValue: CGEventFlags.maskCommand.rawValue)
    static let option = Modifiers(rawValue: CGEventFlags.maskAlternate.rawValue)
    static let control = Modifiers(rawValue: CGEventFlags.maskControl.rawValue)
    static let shift = Modifiers(rawValue: CGEventFlags.maskShift.rawValue)
    static let all: Modifiers = [.command, .option, .control, .shift]

    init(rawValue: UInt64) { self.rawValue = rawValue }

    init(_ flags: CGEventFlags) {
        self.rawValue = flags.rawValue & Modifiers.all.rawValue
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var m: Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        self = m
    }

    var cgFlags: CGEventFlags { CGEventFlags(rawValue: rawValue) }

    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A physical mouse button (CG numbering: 2 = middle, 3 = back, 4 = forward, ...) plus held modifiers.
struct Trigger: Codable, Hashable {
    var button: Int
    var modifiers: Modifiers

    var title: String {
        modifiers.isEmpty ? buttonName : modifiers.symbols + " " + buttonName
    }

    var buttonName: String {
        switch button {
        case 0: return L("Left Button")
        case 1: return L("Right Button")
        case 2: return L("Middle Button")
        case _ where MouseKeys.isKeyButton(button): return L("%@ Button", MouseKeys.symbol(of: button))
        default: return L("Button %d", button + 1)
        }
    }

    /// What the button usually is on a mouse, shown next to its group.
    /// Buttons that arrive as key combos have no drag events, so they can't be click-dragged.
    var canDrag: Bool { !MouseKeys.isKeyButton(button) }

    var role: String {
        switch button {
        case 0: return L("Primary + modifier")
        case 1: return L("Secondary + modifier")
        case 2: return L("Wheel click")
        case 3: return L("Back side")
        case 4: return L("Forward side")
        case _ where MouseKeys.isKeyButton(button): return L("Sends a key combo")
        default: return L("Extra button")
        }
    }
}

enum ClickType: String, Codable, CaseIterable, Identifiable {
    // Declaration order is the row order inside a button group.
    case click, doubleClick, hold, scroll, drag

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return L("Click")
        case .doubleClick: return L("Double Click")
        case .hold: return L("Hold")
        case .scroll: return L("Click and Scroll")
        case .drag: return L("Click and Drag")
        }
    }

    /// Single-shot gestures share the full action menu; drag and scroll have their own continuous actions.
    var isPress: Bool { self == .click || self == .doubleClick || self == .hold }

    var actionGroups: [[ActionKind]] {
        switch self {
        case .click, .doubleClick, .hold: return ActionKind.pressGroups
        case .drag: return [[.dragSpaces, .dragMissionControl, .dragScroll]]
        case .scroll: return [[.scrollZoom, .scrollSpaces, .scrollHorizontal]]
        }
    }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none
    case lookUp, smartZoom, primaryClick, secondaryClick, middleClick
    case primaryDoubleClick, primaryTripleClick, secondaryDoubleClick, secondaryTripleClick
    case back, forward
    case missionControl, appExpose, showDesktop, launchpad, spaceLeft, spaceRight
    case shortcut, mediaKey
    case dragSpaces, dragMissionControl, dragScroll
    case scrollZoom, scrollSpaces, scrollHorizontal

    var id: String { rawValue }

    static let pressGroups: [[ActionKind]] = [
        [.lookUp, .smartZoom, .primaryClick, .secondaryClick, .middleClick],
        [.primaryDoubleClick, .primaryTripleClick, .secondaryDoubleClick, .secondaryTripleClick],
        [.back, .forward],
        [.missionControl, .appExpose, .showDesktop, .launchpad, .spaceLeft, .spaceRight],
    ]

    var title: String {
        switch self {
        case .none: return L("None")
        case .lookUp: return L("Look Up & Quick Look")
        case .smartZoom: return L("Smart Zoom")
        case .primaryClick: return L("Primary Click")
        case .secondaryClick: return L("Secondary Click")
        case .middleClick: return L("Middle Click")
        case .primaryDoubleClick: return L("Left Double Click")
        case .primaryTripleClick: return L("Left Triple Click")
        case .secondaryDoubleClick: return L("Right Double Click")
        case .secondaryTripleClick: return L("Right Triple Click")
        case .back: return L("Back")
        case .forward: return L("Forward")
        case .missionControl: return L("Mission Control")
        case .appExpose: return L("Application Windows")
        case .showDesktop: return L("Show Desktop")
        case .launchpad: return L("Launchpad")
        case .spaceLeft: return L("Move Left a Space")
        case .spaceRight: return L("Move Right a Space")
        case .shortcut: return L("Keyboard Shortcut")
        case .mediaKey: return L("Media Key")
        case .dragSpaces: return L("Move Left or Right a Space")
        case .dragMissionControl: return L("Mission Control & App Windows")
        case .dragScroll: return L("Scroll & Navigate")
        case .scrollZoom: return L("Zoom In or Out")
        case .scrollSpaces: return L("Move Left or Right a Space")
        case .scrollHorizontal: return L("Horizontal Scroll")
        }
    }

    /// Smart Zoom needs a trackpad gesture event that can't be synthesized yet.
    var isAvailable: Bool { self != .smartZoom }
}

/// Special keys from Apple keyboards, posted as NX system-defined events.
enum MediaKey: Int, Codable, CaseIterable {
    case brightnessDown = 3, brightnessUp = 2, previous = 18, playPause = 16, next = 17, mute = 7, volumeDown = 1, volumeUp = 0

    var title: String {
        switch self {
        case .brightnessDown: return L("Decrease Brightness")
        case .brightnessUp: return L("Increase Brightness")
        case .previous: return L("Previous Track")
        case .playPause: return L("Play / Pause")
        case .next: return L("Next Track")
        case .mute: return L("Mute")
        case .volumeDown: return L("Decrease Volume")
        case .volumeUp: return L("Increase Volume")
        }
    }

    var symbol: String {
        switch self {
        case .brightnessDown: return "sun.min"
        case .brightnessUp: return "sun.max"
        case .previous: return "backward"
        case .playPause: return "playpause"
        case .next: return "forward"
        case .mute: return "speaker.slash"
        case .volumeDown: return "speaker.wave.1"
        case .volumeUp: return "speaker.wave.3"
        }
    }
}

struct KeyShortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: Modifiers
    var keyName: String

    var title: String { modifiers.symbols + keyName }
}

struct MouseBinding: Identifiable, Codable, Hashable {
    var id = UUID()
    var trigger: Trigger
    var clickType: ClickType = .click
    var action: ActionKind = .none
    var shortcut: KeyShortcut?
    var mediaKey: MediaKey?

    var actionTitle: String {
        switch action {
        case .shortcut: return shortcut?.title ?? "Keyboard Shortcut…"
        case .mediaKey: return mediaKey?.title ?? "Media Key"
        default: return action.title
        }
    }
}

enum ScrollProfile: String, Codable, CaseIterable {
    case fluid, stepped, linear

    var title: String {
        switch self {
        case .fluid: return L("Trackpad Fluid")
        case .stepped: return L("Natural Stepped")
        case .linear: return L("Direct (Linear)")
        }
    }
}

enum ZoomModifier: String, Codable, CaseIterable {
    case control, command, off

    var title: String {
        switch self {
        case .control: return L("Hold ⌃ Control + Scroll")
        case .command: return L("Hold ⌘ Command + Scroll")
        case .off: return L("Off")
        }
    }
}

struct ScrollSettings: Codable, Equatable {
    var smoothEnabled = true
    var profile: ScrollProfile = .fluid
    var smoothness = 0.75
    var speed = 1.0
    var dynamicAcceleration = true
    var invertDirection = false
    /// Hold ⇧ and scroll to scroll sideways, smoothly like vertical scrolling.
    var horizontalSwipe = true
    /// Hold ⌃⇧ and scroll to go back (up) or forward (down) a page, like a two-finger swipe.
    var swipeNavigation = true
    var zoomModifier: ZoomModifier = .control
    /// The page keeps gliding and slows down after the wheel stops; `smoothness` sets how far.
    var inertia = true

    static let speedRange = 0.5...2.0
}

extension ScrollSettings {
    /// Settings saved by older versions lack newer keys; those fall back to their defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScrollSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        smoothEnabled = try value(.smoothEnabled, defaults.smoothEnabled)
        profile = try value(.profile, defaults.profile)
        smoothness = try value(.smoothness, defaults.smoothness)
        speed = try value(.speed, defaults.speed)
        dynamicAcceleration = try value(.dynamicAcceleration, defaults.dynamicAcceleration)
        invertDirection = try value(.invertDirection, defaults.invertDirection)
        horizontalSwipe = try value(.horizontalSwipe, defaults.horizontalSwipe)
        swipeNavigation = try value(.swipeNavigation, defaults.swipeNavigation)
        zoomModifier = try value(.zoomModifier, defaults.zoomModifier)
        inertia = try value(.inertia, defaults.inertia)
    }
}

extension ClickType {
    /// Tile caption on the Buttons tab ("CLICK + DRAG").
    var caption: String {
        switch self {
        case .click: return L("Click")
        case .doubleClick: return L("Double Click")
        case .hold: return L("Hold")
        case .scroll: return L("Click + Scroll")
        case .drag: return L("Click + Drag")
        }
    }
}

extension ActionKind {
    /// One-line description under the action name on a gesture tile.
    var category: String {
        switch self {
        case .none: return L("Not assigned")
        case .lookUp: return L("Simulates Force Click")
        case .smartZoom: return L("Trackpad gesture")
        case .primaryClick, .secondaryClick, .middleClick: return L("Mouse button")
        case .primaryDoubleClick, .primaryTripleClick, .secondaryDoubleClick, .secondaryTripleClick:
            return L("Several clicks in one press")
        case .back, .forward: return L("Browser & Finder history")
        case .missionControl, .appExpose, .showDesktop, .launchpad: return L("macOS window management")
        case .spaceLeft, .spaceRight, .dragSpaces, .scrollSpaces: return L("Virtual desktop paging")
        case .dragMissionControl: return L("Drag up or down")
        case .shortcut: return L("Custom keyboard shortcut")
        case .mediaKey: return L("Apple keyboard key")
        case .dragScroll: return L("Grab and pan content")
        case .scrollZoom: return L("⌘+ / ⌘− while scrolling")
        case .scrollHorizontal: return L("Wheel scrolls sideways")
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .lookUp: return "magnifyingglass"
        case .smartZoom: return "plus.magnifyingglass"
        case .primaryClick, .secondaryClick, .middleClick: return "cursorarrow.click"
        case .primaryDoubleClick, .primaryTripleClick, .secondaryDoubleClick, .secondaryTripleClick: return "cursorarrow.click.2"
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "macwindow.on.rectangle"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .spaceLeft, .spaceRight, .dragSpaces, .scrollSpaces: return "arrow.left.and.right.square"
        case .dragMissionControl: return "arrow.up.and.down.square"
        case .shortcut: return "command"
        case .mediaKey: return "apple.logo"
        case .dragScroll: return "hand.draw"
        case .scrollZoom: return "plus.magnifyingglass"
        case .scrollHorizontal: return "arrow.left.arrow.right"
        }
    }
}

/// Per-mouse settings, remembered after the mouse disconnects.
struct DeviceProfile: Codable, Equatable {
    var product: String
    var manufacturer: String
    var connection: String
    var hardwareID: String
    var customName: String?
    /// Uses `bindings` instead of the global layout while this mouse is the active one.
    var independent = false
    var bindings: [MouseBinding] = []
    var lastSeen = Date()
    /// This mouse's own scroll settings while it's the active one; nil follows the shared settings.
    var scroll: ScrollSettings?

    var displayName: String { customName ?? product }
}
