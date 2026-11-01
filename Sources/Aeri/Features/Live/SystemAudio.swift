import AudioToolbox
import CoreAudio
import Foundation

/// Output volume and mute of the default output device via Core Audio (no permission needed).
/// Calls `onChange` whenever either changes, from any source: keys, Control Center, other apps.
/// Calls `onActivityChange` the moment any app starts or stops sending audio to the output device,
/// which tells Now Playing to re-check instantly instead of polling.
final class SystemAudio {
    var onChange: ((Float, Bool) -> Void)?
    var onActivityChange: ((Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.notify() }
    private lazy var runningListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self else { return }
        self.onActivityChange?(self.isRunning)
    }
    private lazy var defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, defaultListener)
        attach()
    }

    /// Follows the default output device (e.g. when headphones connect).
    private func attach() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.runningAddress, .main, runningListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &id)
        device = id
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, deviceListener)
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, deviceListener)
        AudioObjectAddPropertyListenerBlock(device, &Self.runningAddress, .main, runningListener)
        onActivityChange?(isRunning)
    }

    /// True while any process is playing audio through the output device.
    var isRunning: Bool {
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &Self.runningAddress, 0, nil, &size, &v)
        return v != 0
    }

    private func notify() { onChange?(volume, muted) }

    var volume: Float {
        get {
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &v)
            return v
        }
        set {
            var v = Float32(min(max(newValue, 0), 1))
            AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    var muted: Bool {
        get {
            var m = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &m)
            return m != 0
        }
        set {
            var m = UInt32(newValue ? 1 : 0)
            AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }
}
