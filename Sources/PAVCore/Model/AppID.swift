/// Identifies an app as the user sees it: its bundle ID, or its executable path
/// when it has none.
public struct AppID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}
