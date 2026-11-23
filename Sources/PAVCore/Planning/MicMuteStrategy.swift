public enum MicAction: Sendable, Equatable {
    case setMute(Bool)
    case setVolume(Float)
    case unsupported
}

/// Mutes a microphone with its own mute control when it has one, otherwise by
/// setting its gain to 0 and restoring it later.
public enum MicMuteStrategy {
    public static let fallbackRestoreVolume: Float = 0.5

    public static func isMuted(_ d: InputDevice) -> Bool {
        if d.muteSettable { return d.muted == true }
        return d.volumeSettable && d.volume == 0
    }

    public static func toggle(_ d: InputDevice, rememberedVolume: Float?) -> (action: MicAction, remember: Float?) {
        if d.muteSettable {
            return (.setMute(!(d.muted ?? false)), rememberedVolume)
        }
        guard d.volumeSettable else { return (.unsupported, rememberedVolume) }
        if isMuted(d) {
            return (.setVolume(rememberedVolume ?? fallbackRestoreVolume), nil)
        }
        return (.setVolume(0), d.volume)
    }
}
