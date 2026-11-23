import PAVCore

public enum Identifiers {
    public static let uidPrefix = "io.github.jalvarezra.hankomix."
    public static let tapUIDPrefix = uidPrefix + "tap."
    public static let aggregateUIDPrefix = uidPrefix + "agg."
    public static let objectName = "Hanko Mix"
    /// Prefix and object name used before the rename to Hanko Mix; leftovers are cleaned up and hidden.
    public static let legacyUIDPrefix = "io.github.perappvolume."
    public static let legacyObjectName = "PerAppVolume"

    /// True for aggregates and other objects created by this app under any of its names.
    public static func isOwnUID(_ uid: String) -> Bool {
        uid.hasPrefix(uidPrefix) || uid.hasPrefix(legacyUIDPrefix)
    }
}

public enum DeviceFilter {
    /// Devices offered in the per-app output menu (AirPlay and aggregates are out of v1).
    public static func isSelectableAsAppOutput(_ device: OutputDevice) -> Bool {
        device.transport != .airPlay && device.transport != .aggregate && !Identifiers.isOwnUID(device.uid)
    }

    /// Devices offered as the system default output (AirPlay included).
    public static func isSelectableAsSystemOutput(_ device: OutputDevice) -> Bool {
        device.canBeDefault && !Identifiers.isOwnUID(device.uid)
    }

    /// Devices offered as the system default microphone.
    public static func isSelectableAsSystemInput(_ device: InputDevice) -> Bool {
        device.canBeDefault && !Identifiers.isOwnUID(device.uid)
    }
}
