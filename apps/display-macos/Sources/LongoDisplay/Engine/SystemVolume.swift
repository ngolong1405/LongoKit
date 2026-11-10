import CoreAudio
import AudioToolbox

/// The Mac's own output volume (the default output device, like the volume keys), for the built-in display's
/// speaker slider. External monitors' speakers go over DDC instead.
enum SystemVolume {
    private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static func outputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutput = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// 0…1, or nil when the output device has no volume control (e.g. some HDMI outputs).
    static func get() -> Double? {
        guard let device = outputDevice(), AudioObjectHasProperty(device, &address) else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume)
    }

    private static var watchedDevice: AudioDeviceID?
    private static var volumeListener: AudioObjectPropertyListenerBlock?

    /// Calls `changed` (on the main queue) when the output volume or the output device changes, so the app
    /// doesn't have to keep asking.
    static func observe(_ changed: @escaping () -> Void) {
        var defaultOutput = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let volume: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        volumeListener = volume
        func watchOutput() {
            if let old = watchedDevice { AudioObjectRemovePropertyListenerBlock(old, &address, .main, volume) }
            watchedDevice = outputDevice()
            if let device = watchedDevice, AudioObjectHasProperty(device, &address) {
                AudioObjectAddPropertyListenerBlock(device, &address, .main, volume)
            }
        }
        watchOutput()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, .main) { _, _ in
            watchOutput()
            changed()
        }
    }

    static func set(_ value: Double) {
        guard let device = outputDevice() else { return }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var volume = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }
}
