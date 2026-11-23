public enum TransportKind: String, Sendable {
    case builtIn, usb, bluetooth, airPlay, aggregate, virtual, hdmi, displayPort, thunderbolt, other
}

public struct OutputDevice: Sendable, Hashable {
    public var uid: String
    public var name: String
    public var transport: TransportKind
    public var sampleRate: Double
    public var channels: Int
    /// False for devices macOS won't use as the system default (hidden in System Settings).
    public var canBeDefault: Bool

    public init(uid: String, name: String, transport: TransportKind, sampleRate: Double, channels: Int, canBeDefault: Bool = true) {
        self.uid = uid
        self.name = name
        self.transport = transport
        self.sampleRate = sampleRate
        self.channels = channels
        self.canBeDefault = canBeDefault
    }
}

/// One app as shown to the user: possibly several audio processes (helpers).
public struct AppGroup: Sendable, Hashable {
    public var id: AppID
    public var displayName: String
    public var processObjectIDs: Set<UInt32>
    public var isPlaying: Bool
    public var outputDeviceUIDs: [String]

    public init(id: AppID, displayName: String, processObjectIDs: Set<UInt32>, isPlaying: Bool, outputDeviceUIDs: [String]) {
        self.id = id
        self.displayName = displayName
        self.processObjectIDs = processObjectIDs
        self.isPlaying = isPlaying
        self.outputDeviceUIDs = outputDeviceUIDs
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    public var apps: [AppGroup]
    public var devices: [OutputDevice]
    public var defaultOutputUID: String?
    /// PerAppVolume's own Core Audio process objects; always excluded from taps.
    public var ownProcessObjectIDs: Set<UInt32>
    public var inputDevices: [InputDevice]
    public var defaultInputUID: String?

    public init(apps: [AppGroup], devices: [OutputDevice], defaultOutputUID: String?, ownProcessObjectIDs: Set<UInt32> = [],
                inputDevices: [InputDevice] = [], defaultInputUID: String? = nil) {
        self.apps = apps
        self.devices = devices
        self.defaultOutputUID = defaultOutputUID
        self.ownProcessObjectIDs = ownProcessObjectIDs
        self.inputDevices = inputDevices
        self.defaultInputUID = defaultInputUID
    }

    public func device(uid: String) -> OutputDevice? { devices.first { $0.uid == uid } }
}
