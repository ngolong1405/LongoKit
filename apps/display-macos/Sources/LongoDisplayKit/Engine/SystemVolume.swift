import CoreAudio
import AudioToolbox

/// The Mac's sound outputs: which one plays (macOS sends sound to one at a time), switching to another, and the
/// built-in speakers' volume for the built-in display's slider. External monitors' own speakers go over DDC.
enum SystemVolume {
    /// A device sound can play through: the built-in speakers, or a monitor's HDMI / DisplayPort audio.
    struct Output: Equatable {
        let id: AudioDeviceID
        let name: String
        let isBuiltIn: Bool
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The device macOS plays through now.
    static func playing() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// Plays through `device` from now on, like choosing it in Control Center.
    static func play(through device: AudioDeviceID) {
        var device = device
        var defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    }

    /// Built-in speakers and monitors' HDMI / DisplayPort audio (no virtual or Bluetooth devices).
    static func outputs() -> [Output] {
        var devices = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devices, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devices, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }
            var transport = UInt32(0)
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = address(kAudioDevicePropertyTransportType)
            AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
            let builtIn = transport == kAudioDeviceTransportTypeBuiltIn
            guard builtIn || transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort else { return nil }
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = address(kAudioObjectPropertyName)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return Output(id: id, name: (name?.takeRetainedValue() as String?) ?? "", isBuiltIn: builtIn)
        }
    }

    /// A device's volume, 0…1; nil when it has none.
    static func get(_ device: AudioDeviceID) -> Double? {
        guard AudioObjectHasProperty(device, &volumeAddress) else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume)
    }

    static func set(_ value: Double, on device: AudioDeviceID) {
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr, settable.boolValue else { return }
        var volume = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }

    private static var watchedSpeakers: AudioDeviceID?
    private static var volumeListener: AudioObjectPropertyListenerBlock?

    /// Calls `changed` (on the main queue) when the speakers' volume, the device that plays, or the list of devices
    /// changes, so the app doesn't have to keep asking.
    static func observe(_ changed: @escaping () -> Void) {
        let volume: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        volumeListener = volume
        func watchSpeakers() {
            if let old = watchedSpeakers { AudioObjectRemovePropertyListenerBlock(old, &volumeAddress, .main, volume) }
            watchedSpeakers = outputs().first(where: \.isBuiltIn)?.id
            if let device = watchedSpeakers, AudioObjectHasProperty(device, &volumeAddress) {
                AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, volume)
            }
        }
        watchSpeakers()
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var changes = address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &changes, .main) { _, _ in
                watchSpeakers()
                changed()
            }
        }
    }
}
