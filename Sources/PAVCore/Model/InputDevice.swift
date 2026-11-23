/// A microphone / input device and the controls it exposes.
public struct InputDevice: Sendable, Hashable {
    public var uid: String
    public var name: String
    public var transport: TransportKind
    /// 0…1, or nil when the device reports no input volume.
    public var volume: Float?
    public var volumeSettable: Bool
    public var muted: Bool?
    public var muteSettable: Bool
    /// False for devices macOS won't use as the system default input.
    public var canBeDefault: Bool

    public init(uid: String, name: String, transport: TransportKind, volume: Float?, volumeSettable: Bool, muted: Bool?, muteSettable: Bool,
                canBeDefault: Bool = true) {
        self.canBeDefault = canBeDefault
        self.uid = uid
        self.name = name
        self.transport = transport
        self.volume = volume
        self.volumeSettable = volumeSettable
        self.muted = muted
        self.muteSettable = muteSettable
    }
}
