import AppKit

/// The app's sounds, all macOS's own so they feel at home: the screenshot shutter, the recording start and stop,
/// pause, resume, the countdown's ticks and copied text. Loaded the first time each plays. The app's own sounds are
/// never in a recording of the Mac's sound.
enum Sound: CaseIterable {
    case shutter, tick, start, pause, resume, stop, text

    private var path: String {
        let system = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/"
        switch self {
        case .shutter: return system + "Screen Capture.aif"
        case .start: return system + "begin_record.caf"
        case .stop: return system + "end_record.caf"
        case .pause: return system + "media_paused.caf"
        case .resume: return "/System/Library/Sounds/Pop.aiff"
        case .tick, .text: return "/System/Library/Sounds/Tink.aiff"
        }
    }

    private var volume: Float {
        switch self {
        case .tick: return 0.45
        case .text, .resume: return 0.6
        default: return 1
        }
    }

    @MainActor private static var loaded: [Sound: NSSound] = [:]

    /// Plays unless sounds are off; a sound macOS doesn't have is skipped.
    @MainActor func play(if enabled: Bool) {
        guard enabled else { return }
        let sound = Self.loaded[self] ?? NSSound(contentsOfFile: path, byReference: true)
        guard let sound else { return }
        Self.loaded[self] = sound
        sound.volume = volume
        sound.stop()
        sound.play()
    }

    /// Whether macOS has the sound's file.
    var isAvailable: Bool { FileManager.default.fileExists(atPath: path) }
}
