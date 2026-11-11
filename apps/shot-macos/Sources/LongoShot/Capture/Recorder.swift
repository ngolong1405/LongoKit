import AVFoundation
import ScreenCaptureKit

/// Records part of the screen or one window to an MP4, with ScreenCaptureKit feeding AVAssetWriter. The stream only
/// exists while recording; like captures, the app's own windows (the recording bar, the outline) are left out.
/// Samples and the writer are only touched on `queue`, which is what makes it safe to hand between threads.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Options {
        var framesPerSecond = 30
        var systemAudio = false
        var microphone = false
        var showsCursor = true
        var showsClicks = false
    }

    enum Failure: LocalizedError {
        case notFound, nothingRecorded

        var errorDescription: String? {
            switch self {
            case .notFound: return "The screen or window is no longer there."
            case .nothingRecorded: return "Nothing was recorded."
            }
        }
    }

    let url: URL
    /// Called on the recorder's queue when macOS stops the stream (a window closed, permission taken away…).
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let systemAudio: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "LongoShot.recorder")
    private var started = false
    /// While paused, samples are dropped; when it goes on, later samples are moved back by the time spent paused,
    /// so the video runs on without a gap.
    private var pausedAt: CMTime?
    private var pausedTotal = CMTime.zero

    /// Starts recording `selection` into a new file at `url`. `paused` gets the stream going without recording yet
    /// (during a countdown), so `resume()` starts it right away.
    static func start(_ selection: Selection, options: Options, to url: URL, paused: Bool = false) async throws -> Recorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let config = SCStreamConfiguration()
        let filter: SCContentFilter
        let size: CGSize
        switch selection {
        case let .area(displayID, rect, scale):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure.notFound }
            let mine = content.applications.filter { $0.processID == getpid() }
            filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
            let area = rect.isNull ? CGRect(x: 0, y: 0, width: display.width, height: display.height) : rect
            if !rect.isNull { config.sourceRect = area }
            size = CGSize(width: area.width * scale, height: area.height * scale)
        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw Failure.notFound }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            size = CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale)
        }
        let (width, height) = videoSize(size)
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.framesPerSecond))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.showsCursor = options.showsCursor
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        if #available(macOS 15.0, *) {
            config.captureMicrophone = options.microphone
            config.showMouseClicks = options.showsClicks && options.showsCursor
        }

        let recorder = try Recorder(url: url, width: width, height: height, options: options)
        if paused { recorder.pausedAt = now }
        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        if options.systemAudio { try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: recorder.queue) }
        if #available(macOS 15.0, *), options.microphone {
            try stream.addStreamOutput(recorder, type: .microphone, sampleHandlerQueue: recorder.queue)
        }
        try await stream.startCapture()
        recorder.stream = stream
        return recorder
    }

    /// Video sizes must be even; anything wider or taller than H.264 allows (4096) is encoded as HEVC.
    static func videoSize(_ size: CGSize) -> (Int, Int) {
        func even(_ value: CGFloat) -> Int { max(2, Int(value.rounded()) & ~1) }
        return (even(size.width), even(size.height))
    }

    static func codec(width: Int, height: Int) -> AVVideoCodecType {
        max(width, height) > 4096 ? .hevc : .h264
    }

    private init(url: URL, width: Int, height: Int, options: Options) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let pixels = Double(width * height) * Double(options.framesPerSecond)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: Self.codec(width: width, height: height),
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // About 0.1 bit per pixel per frame: sharp text without huge files.
                AVVideoAverageBitRateKey: Int(min(max(pixels * 0.1, 2_000_000), 40_000_000)),
                AVVideoExpectedSourceFrameRateKey: options.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: options.framesPerSecond * 2,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        func audioInput(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: channels * 64_000,
            ])
            input.expectsMediaDataInRealTime = true
            return input
        }
        systemAudio = options.systemAudio ? audioInput(channels: 2) : nil
        var microphone: AVAssetWriterInput?
        if #available(macOS 15.0, *), options.microphone { microphone = audioInput(channels: 1) }
        self.microphone = microphone
        super.init()
        for input in [video, systemAudio, microphone].compactMap({ $0 }) where writer.canAdd(input) {
            writer.add(input)
        }
    }

    private static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    func pause() {
        queue.async { [self] in
            if pausedAt == nil { pausedAt = Self.now }
        }
    }

    func resume() {
        queue.async { [self] in
            guard let pausedAt else { return }
            // Before the first frame there's nothing to close the gap to: the video just starts later.
            if started { pausedTotal = pausedTotal + (Self.now - pausedAt) }
            self.pausedAt = nil
        }
    }

    /// `sample` with its times moved back by the time spent paused.
    private func shifted(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard pausedTotal != .zero else { return sample }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for index in timing.indices {
            timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - pausedTotal
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - pausedTotal
            }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }

    /// Ends the recording and finishes the file. Returns its URL.
    func stop() async throws -> URL {
        try? await stream?.stopCapture()
        stream = nil
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard started else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    return continuation.resume(throwing: Failure.nothingRecorded)
                }
                // The screen only sends frames when something changes; hold the last one until now (or the pause).
                writer.endSession(atSourceTime: (pausedAt ?? Self.now) - pausedTotal)
                for input in [video, systemAudio, microphone].compactMap({ $0 }) { input.markAsFinished() }
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: writer.error ?? Failure.nothingRecorded)
                    }
                }
            }
        }
    }

    // MARK: - SCStreamOutput, SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sample.isValid, pausedAt == nil, let sample = shifted(sample) else { return }
        switch type {
        case .screen:
            // Only complete frames carry a picture; idle ones just say nothing changed.
            guard let info = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = info.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            if !started {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: sample.presentationTimeStamp)
                started = true
            }
            if video.isReadyForMoreMediaData { video.append(sample) }
        case .audio:
            if started, let systemAudio, systemAudio.isReadyForMoreMediaData { systemAudio.append(sample) }
        default:
            if started, let microphone, microphone.isReadyForMoreMediaData { microphone.append(sample) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }
}
