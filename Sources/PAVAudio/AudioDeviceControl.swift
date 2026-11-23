import CoreAudio
import Foundation
import PAVCore

/// Reads and changes system-wide device settings: default output/input, and a
/// microphone's gain and mute. Never opens an audio stream.
public enum AudioDeviceControl {
    public static func setDefaultOutput(uid: String) throws {
        // Only the default output, like System Settings' Output picker: alerts follow it
        // when the user chose that, and keep a fixed device otherwise.
        try AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, try deviceID(uid: uid))
    }

    public static func setDefaultInput(uid: String) throws {
        try AudioObjectID.system.write(kAudioHardwarePropertyDefaultInputDevice, try deviceID(uid: uid))
    }

    public static func setInputVolume(uid: String, _ volume: Float) throws {
        let id = try deviceID(uid: uid)
        let elements = volumeElements(of: id)
        guard !elements.isEmpty else {
            throw AudioError(status: kAudioHardwareUnsupportedOperationError, context: "This microphone doesn't support volume control")
        }
        let clamped = Float32(min(max(volume, 0), 1))
        for element in elements {
            try id.write(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element, clamped)
        }
    }

    public static func setInputMute(uid: String, _ muted: Bool) throws {
        try deviceID(uid: uid).write(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, UInt32(muted ? 1 : 0))
    }

    public static func averageOfChannelVolumes(_ values: [Float]) -> Float? {
        values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    // MARK: Reading (used by AudioSystemMonitor)

    static func inputDevice(id: AudioObjectID, uid: String, name: String, transport: TransportKind) -> InputDevice {
        let elements = volumeElements(of: id)
        let readable = elements.isEmpty ? readableVolumeElements(of: id) : elements
        let volumes = readable.compactMap {
            try? id.read(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: $0, default: Float32(0))
        }
        let muteSettable = id.isSettable(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        let muted = id.has(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
            ? (try? id.read(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, default: UInt32(0))).map { $0 != 0 }
            : nil
        return InputDevice(uid: uid, name: name, transport: transport, volume: averageOfChannelVolumes(volumes),
                           volumeSettable: !elements.isEmpty, muted: muted, muteSettable: muteSettable)
    }

    /// The main element when it is settable, otherwise every settable channel element.
    static func volumeElements(of id: AudioObjectID) -> [AudioObjectPropertyElement] {
        if id.isSettable(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput) {
            return [kAudioObjectPropertyElementMain]
        }
        let channels = (try? id.channelCount(scope: kAudioObjectPropertyScopeInput)) ?? 0
        guard channels > 0 else { return [] }
        return (1...channels).map(AudioObjectPropertyElement.init).filter {
            id.isSettable(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: $0)
        }
    }

    private static func readableVolumeElements(of id: AudioObjectID) -> [AudioObjectPropertyElement] {
        if id.has(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput) { return [kAudioObjectPropertyElementMain] }
        let channels = (try? id.channelCount(scope: kAudioObjectPropertyScopeInput)) ?? 0
        guard channels > 0 else { return [] }
        return (1...channels).map(AudioObjectPropertyElement.init).filter {
            id.has(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: $0)
        }
    }

    static func deviceID(uid: String) throws -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(.system, &addr, UInt32(MemoryLayout<CFString>.size), qualifier, &size, &id)
        }, "find device \(uid)")
        guard id != kAudioObjectUnknown else {
            throw AudioError(status: kAudioHardwareBadDeviceError, context: "device \(uid) is not connected")
        }
        return id
    }
}
