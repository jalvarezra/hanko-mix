import Foundation

/// On-disk settings document (`settings.json`).
public struct SettingsFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = SettingsFile.currentVersion
    public var apps: [String: AppSettings] = [:]
    public var devices: [String: DeviceSettings] = [:]
    public var launchAtLogin = false
    public var permissionExplained = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case version, apps, devices, launchAtLogin, permissionExplained }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        apps = try c.decodeIfPresent([String: AppSettings].self, forKey: .apps) ?? [:]
        devices = try c.decodeIfPresent([String: DeviceSettings].self, forKey: .devices) ?? [:]
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        permissionExplained = try c.decodeIfPresent(Bool.self, forKey: .permissionExplained) ?? false
    }
}

/// Loads and saves `SettingsFile`, recovering from corrupt files and refusing to
/// overwrite files written by a newer version of the app.
public final class SettingsStore: @unchecked Sendable {
    public enum LoadOutcome: Equatable {
        case fresh, loaded, recoveredFromCorrupt(backup: URL), newerVersion(Int)
    }

    public static let debounceInterval: TimeInterval = 0.5

    public private(set) var file = SettingsFile()
    public private(set) var isReadOnly = false

    private let directory: URL
    private let queue = DispatchQueue(label: "io.github.perappvolume.settings")
    private var pendingWrite: DispatchWorkItem?

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerAppVolume", isDirectory: true)
    }

    private var fileURL: URL { directory.appendingPathComponent("settings.json") }

    public func load() -> LoadOutcome {
        guard let data = try? Data(contentsOf: fileURL) else {
            file = SettingsFile()
            return .fresh
        }
        struct VersionProbe: Decodable { var version: Int }
        if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data), probe.version > SettingsFile.currentVersion {
            file = SettingsFile()
            isReadOnly = true
            return .newerVersion(probe.version)
        }
        do {
            file = try JSONDecoder().decode(SettingsFile.self, from: data)
            return .loaded
        } catch {
            file = SettingsFile()
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = directory.appendingPathComponent("settings.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return .recoveredFromCorrupt(backup: backup)
        }
    }

    /// Applies `change` in memory and schedules a debounced atomic write.
    public func mutate(_ change: (inout SettingsFile) -> Void) {
        change(&file)
        guard !isReadOnly else { return }
        pendingWrite?.cancel()
        let snapshot = file   // write a copy so the queue never reads `file` while it changes
        let work = DispatchWorkItem { [weak self] in try? self?.write(snapshot) }
        pendingWrite = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    /// Writes immediately (no-op when read-only).
    public func flush() throws {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard !isReadOnly else { return }
        try write(file)
    }

    private func write(_ snapshot: SettingsFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
