import AppKit
import Observation
import PAVAudio
import PAVCore

struct AppRow: Identifiable, Equatable {
    var id: AppID
    var name: String
    var icon: NSImage?
    var volume: Float
    var muted: Bool
    var outputUID: String?
    var isPlaying: Bool
    var status: TapStatus?
}

@MainActor @Observable
final class AppState {
    private(set) var rows: [AppRow] = []
    private(set) var defaultDevice: OutputDevice?
    private(set) var selectableDevices: [OutputDevice] = []
    private(set) var permissionNotice: PermissionGate.Notice?
    private(set) var settings: SettingsFile

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let monitor: AudioSystemMonitor
    @ObservationIgnored private let coordinator: AudioCoordinator
    @ObservationIgnored private var snapshot = SystemSnapshot(apps: [], devices: [], defaultOutputUID: nil)
    @ObservationIgnored private var statuses: [TapKind: TapStatus] = [:]
    @ObservationIgnored private var seenThisSession: [AppID: String] = [:]
    @ObservationIgnored private var icons: [AppID: NSImage] = [:]
    @ObservationIgnored private var permissionDeferred = false

    init(store: SettingsStore, monitor: AudioSystemMonitor, coordinator: AudioCoordinator) {
        self.store = store
        self.monitor = monitor
        self.coordinator = coordinator
        _ = store.load()
        settings = store.file
    }

    static func live() -> AppState {
        let coordinator = AudioCoordinator(backend: CoreAudioBackend())
        let monitor = AudioSystemMonitor(queue: coordinator.queue)
        return AppState(store: SettingsStore(directory: SettingsStore.defaultDirectory), monitor: monitor, coordinator: coordinator)
    }

    func start() {
        coordinator.cleanupStale()
        monitor.start { [weak self] snapshot in
            Task { @MainActor in self?.receive(snapshot) }
        }
    }

    func shutdown() {
        monitor.stop()
        coordinator.shutdown()
        try? store.flush()
    }

    // MARK: Intents

    func setVolume(_ volume: Float, for id: AppID) {
        let clamped = Snap.volume(min(max(volume, AppSettings.volumeRange.lowerBound), AppSettings.volumeRange.upperBound))
        mutateApp(id) { $0.volume = clamped }
    }

    func resetVolume(for id: AppID) { setVolume(1, for: id) }

    func setMuted(_ muted: Bool, for id: AppID) { mutateApp(id) { $0.muted = muted } }

    func setOutput(_ uid: String?, for id: AppID) { mutateApp(id) { $0.outputDeviceUID = uid } }

    func updateDeviceSettings(_ uid: String, _ change: (inout DeviceSettings) -> Void) {
        store.mutate { file in
            var device = file.devices[uid] ?? DeviceSettings()
            change(&device)
            file.devices[uid] = device
        }
        settingsChanged()
    }

    func forgetApp(_ id: AppID) {
        store.mutate { $0.apps[id.rawValue] = nil }
        settingsChanged()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        store.mutate { $0.launchAtLogin = enabled }
        settings = store.file
    }

    func acceptPermissionExplanation() {
        store.mutate { $0.permissionExplained = true }
        settingsChanged()
    }

    func deferPermissionExplanation() {
        permissionDeferred = true
        permissionNotice = nil
    }

    func deviceSettings(for uid: String) -> DeviceSettings { settings.devices[uid] ?? DeviceSettings() }

    func device(uid: String) -> OutputDevice? { snapshot.device(uid: uid) }

    var allOutputDevices: [OutputDevice] { snapshot.devices }

    // MARK: Pipeline

    private func mutateApp(_ id: AppID, _ change: (inout AppSettings) -> Void) {
        permissionDeferred = false
        store.mutate { file in
            var app = file.apps[id.rawValue] ?? AppSettings(displayName: self.seenThisSession[id] ?? id.rawValue)
            change(&app)
            file.apps[id.rawValue] = app
        }
        settingsChanged()
    }

    private func receive(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        rememberPlayingApps(snapshot)
        settingsChanged()
    }

    /// Saves `displayName` and `lastSeen` for apps that play (at most hourly per app).
    private func rememberPlayingApps(_ snapshot: SystemSnapshot) {
        let now = Date()
        for app in snapshot.apps where app.isPlaying {
            seenThisSession[app.id] = app.displayName
            let existing = store.file.apps[app.id.rawValue]
            if existing == nil || existing!.lastSeen.map({ now.timeIntervalSince($0) > 3600 }) ?? true {
                store.mutate { file in
                    var s = file.apps[app.id.rawValue] ?? AppSettings(displayName: app.displayName)
                    s.displayName = app.displayName
                    s.lastSeen = now
                    file.apps[app.id.rawValue] = s
                }
            }
        }
    }

    private func settingsChanged() {
        settings = store.file
        let appSettings = Dictionary(uniqueKeysWithValues: settings.apps.map { (AppID($0.key), $0.value) })
        let explained = settings.permissionExplained
        let permission = AudioCapturePermission.status()
        let allowTaps = PermissionGate.decide(explained: explained, status: permission, wantsTaps: true).allowTaps
        let snapshot = snapshot
        rebuildRows()
        coordinator.apply(snapshot: snapshot, appSettings: appSettings, deviceSettings: settings.devices,
                          allowTaps: allowTaps) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.statuses = result.statuses
                let notice = PermissionGate.decide(explained: explained, status: permission,
                                                   wantsTaps: result.plannedCount > 0).notice
                self.permissionNotice = (notice == .explain && self.permissionDeferred) ? nil : notice
                self.rebuildRows()
            }
        }
    }

    private func rebuildRows() {
        defaultDevice = snapshot.defaultOutputUID.flatMap { snapshot.device(uid: $0) }
        selectableDevices = snapshot.devices.filter(DeviceFilter.isSelectableAsAppOutput)
        let playing = snapshot.apps.filter(\.isPlaying)
        let playingIDs = Set(playing.map(\.id))
        var result = playing.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { row(id: $0.id, name: $0.displayName, playing: true) }
        let recent = seenThisSession.filter { !playingIDs.contains($0.key) }
            .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        result += recent.map { row(id: $0.key, name: $0.value, playing: false) }
        if result != rows { rows = result }
    }

    private func row(id: AppID, name: String, playing: Bool) -> AppRow {
        let s = settings.apps[id.rawValue]
        return AppRow(id: id, name: name, icon: icon(for: id), volume: s?.volume ?? 1, muted: s?.muted ?? false,
                      outputUID: s?.outputDeviceUID, isPlaying: playing, status: statuses[.app(id)])
    }

    private func icon(for id: AppID) -> NSImage? {
        if let cached = icons[id] { return cached }
        let workspace = NSWorkspace.shared
        let image: NSImage? = if let url = workspace.urlForApplication(withBundleIdentifier: id.rawValue) {
            workspace.icon(forFile: url.path)
        } else if id.rawValue.hasPrefix("/") {
            workspace.icon(forFile: id.rawValue)
        } else {
            nil
        }
        image?.size = NSSize(width: 20, height: 20)
        icons[id] = image
        return image
    }
}
