import PAVCore

public enum Identifiers {
    public static let uidPrefix = "io.github.perappvolume."
    public static let tapUIDPrefix = uidPrefix + "tap."
    public static let aggregateUIDPrefix = uidPrefix + "agg."
    public static let objectName = "PerAppVolume"
}

public enum DeviceFilter {
    /// Devices offered in the per-app output menu (AirPlay and aggregates are out of v1).
    public static func isSelectableAsAppOutput(_ device: OutputDevice) -> Bool {
        device.transport != .airPlay && device.transport != .aggregate && !device.uid.hasPrefix(Identifiers.uidPrefix)
    }
}
