import Foundation

/// Remembered per-app settings, keyed by `AppID` in the settings file.
public struct AppSettings: Codable, Sendable, Equatable {
    public static let volumeRange: ClosedRange<Float> = 0...2

    public var volume: Float = 1
    public var muted = false
    /// User-assigned output device UID; `nil` means automatic (whatever the app uses).
    public var outputDeviceUID: String? = nil
    public var displayName: String
    public var lastSeen: Date? = nil

    public init(displayName: String) {
        self.displayName = displayName
    }
}
