import Foundation

/// Apps that played audio this session and are silent now. They stay in the
/// menu for a while so their controls remain reachable, and are hidden once
/// they have been silent longer than `idleTimeout`. Nothing is forgotten:
/// an app that plays again shows up again.
public struct RecentApps: Sendable {
    public static let defaultIdleTimeout: TimeInterval = 10 * 60

    public var idleTimeout: TimeInterval
    private var names: [AppID: String] = [:]
    private var lastActive: [AppID: Date] = [:]
    private var playing: Set<AppID> = []

    public init(idleTimeout: TimeInterval = defaultIdleTimeout) {
        self.idleTimeout = idleTimeout
    }

    /// Feed every snapshot's apps. An app is active while it plays and at the
    /// moment it stops (or quits), so idle time counts from when it went silent.
    public mutating func observe(_ apps: [AppGroup], at now: Date) {
        var playingNow: Set<AppID> = []
        for app in apps where app.isPlaying {
            playingNow.insert(app.id)
            names[app.id] = app.displayName
            lastActive[app.id] = now
        }
        for id in playing.subtracting(playingNow) { lastActive[id] = now }
        playing = playingNow
    }

    /// Silent apps still within `idleTimeout`, sorted by name.
    public func visibleIdle(excluding playingIDs: Set<AppID>, at now: Date) -> [(id: AppID, name: String)] {
        lastActive
            .filter { !playingIDs.contains($0.key) && now.timeIntervalSince($0.value) <= idleTimeout }
            .compactMap { id, _ in names[id].map { (id: id, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The display name of an app that has played this session.
    public func name(for id: AppID) -> String? { names[id] }
}
