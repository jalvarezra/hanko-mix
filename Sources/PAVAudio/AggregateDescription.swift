import CoreAudio

/// Composition dictionary for a private aggregate device that plays one tap on one
/// output device (spec §8.3).
public enum AggregateDescription {
    public static func make(uid: String, outputDeviceUID: String, tapUID: String) -> [String: Any] {
        [
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceNameKey: Identifiers.objectName,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID, kAudioSubDeviceDriftCompensationKey: 1],
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: 1],
            ],
            kAudioAggregateDeviceTapAutoStartKey: 1,
        ]
    }
}
