import AVFoundation

/// The app's sounds, all macOS's own so they feel at home: the screenshot shutter, the recording start and stop,
/// pause, resume, the countdown's ticks and copied text. The app's own sounds are never in a recording of the Mac's
/// sound.
///
/// They play on a queue of their own: the first sound wakes the audio hardware (a fraction of a second, longer for
/// Bluetooth headphones or a display's speakers), and the capture shouldn't wait for that.
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

    private static let queue = DispatchQueue(label: "com.longokit.shot.sounds", qos: .userInitiated)
    /// Only touched on `queue`.
    nonisolated(unsafe) private static var players: [Sound: AVAudioPlayer] = [:]

    /// Plays unless sounds are off; a sound macOS doesn't have is skipped. Returns at once.
    func play(if enabled: Bool) {
        guard enabled else { return }
        let sound = self
        Self.queue.async {
            guard let player = Self.player(sound) else { return }
            player.currentTime = 0
            player.play()
        }
    }

    /// Loads every sound ahead and readies the audio hardware, so the first shutter plays right away.
    static func preload() {
        queue.async { for sound in allCases { _ = player(sound) } }
    }

    /// The sound's player, loaded and prepared the first time (on `queue`).
    private static func player(_ sound: Sound) -> AVAudioPlayer? {
        if let player = players[sound] { return player }
        guard let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: sound.path)) else { return nil }
        player.volume = sound.volume
        player.prepareToPlay()
        players[sound] = player
        return player
    }

    /// Whether macOS has the sound's file.
    var isAvailable: Bool { FileManager.default.fileExists(atPath: path) }
}
