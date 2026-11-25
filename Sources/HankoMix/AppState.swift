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
    private(set) var systemOutputDevices: [OutputDevice] = []
    private(set) var inputDevices: [InputDevice] = []
    private(set) var defaultInput: InputDevice?
    private(set) var deviceError: String?
    private(set) var permissionNotice: PermissionGate.Notice?
    private(set) var settings: SettingsFile

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let monitor: AudioSystemMonitor
    @ObservationIgnored private let coordinator: AudioCoordinator
    @ObservationIgnored private var snapshot = SystemSnapshot(apps: [], devices: [], defaultOutputUID: nil)
    @ObservationIgnored private var statuses: [TapKind: TapStatus] = [:]
    @ObservationIgnored private var recentApps = RecentApps()
    @ObservationIgnored private var idleRefreshTimer: Timer?
    @ObservationIgnored private var icons: [AppID: NSImage] = [:]
    @ObservationIgnored private var permissionDeferred = false
    @ObservationIgnored private var rememberedMicVolumes: [String: Float] = [:]

    init(store: SettingsStore, monitor: AudioSystemMonitor, coordinator: AudioCoordinator) {
        self.store = store
        self.monitor = monitor
        self.coordinator = coordinator
        SettingsStore.migrateLegacyDirectory()
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
        // Silent apps hide after a while even when no new snapshot arrives.
        idleRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildRows() }
        }
    }

    func shutdown() {
        idleRefreshTimer?.invalidate()
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

    // MARK: System devices

    func setSystemOutput(_ uid: String) {
        performDeviceWrite { try AudioDeviceControl.setDefaultOutput(uid: uid) }
    }

    func setSystemInput(_ uid: String) {
        performDeviceWrite { try AudioDeviceControl.setDefaultInput(uid: uid) }
    }

    func setMicVolume(_ volume: Float) {
        guard let uid = defaultInput?.uid else { return }
        rememberedMicVolumes[uid] = nil   // a manual change replaces any pre-mute memory
        performDeviceWrite { try AudioDeviceControl.setInputVolume(uid: uid, volume) }
    }

    func toggleMicMute() {
        guard let mic = defaultInput else { return }
        let (action, remember) = MicMuteStrategy.toggle(mic, rememberedVolume: rememberedMicVolumes[mic.uid])
        rememberedMicVolumes[mic.uid] = remember
        let uid = mic.uid
        switch action {
        case .setMute(let muted): performDeviceWrite { try AudioDeviceControl.setInputMute(uid: uid, muted) }
        case .setVolume(let volume): performDeviceWrite { try AudioDeviceControl.setInputVolume(uid: uid, volume) }
        case .unsupported: break
        }
    }

    /// Runs a device write off the main thread; the next snapshot refreshes the UI.
    private func performDeviceWrite(_ write: @escaping @Sendable () throws -> Void) {
        deviceError = nil
        coordinator.queue.async {
            do { try write() } catch {
                let message = "\(error)"
                Task { @MainActor [weak self] in self?.deviceError = message }
            }
        }
    }

    func deviceSettings(for uid: String) -> DeviceSettings { settings.devices[uid] ?? DeviceSettings() }

    func device(uid: String) -> OutputDevice? { snapshot.device(uid: uid) }

    var allOutputDevices: [OutputDevice] { snapshot.devices }

    // MARK: Pipeline

    private func mutateApp(_ id: AppID, _ change: (inout AppSettings) -> Void) {
        permissionDeferred = false
        store.mutate { file in
            var app = file.apps[id.rawValue] ?? AppSettings(displayName: self.recentApps.name(for: id) ?? id.rawValue)
            change(&app)
            file.apps[id.rawValue] = app
        }
        settingsChanged()
    }

    private func receive(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        recentApps.observe(snapshot.apps, at: Date())
        rememberPlayingApps(snapshot)
        settingsChanged()
    }

    /// Saves `displayName` and `lastSeen` for apps that play (at most hourly per app).
    private func rememberPlayingApps(_ snapshot: SystemSnapshot) {
        let now = Date()
        for app in snapshot.apps where app.isPlaying {
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
        systemOutputDevices = snapshot.devices.filter {
            DeviceFilter.isSelectableAsSystemOutput($0) || $0.uid == snapshot.defaultOutputUID
        }
        // Offer devices macOS accepts as default, plus the current default in any case.
        let selectableInputs = snapshot.inputDevices.filter {
            DeviceFilter.isSelectableAsSystemInput($0) || $0.uid == snapshot.defaultInputUID
        }
        if inputDevices != selectableInputs { inputDevices = selectableInputs }
        let newDefaultInput = snapshot.defaultInputUID.flatMap { uid in snapshot.inputDevices.first { $0.uid == uid } }
        if defaultInput != newDefaultInput { defaultInput = newDefaultInput }
        let playing = snapshot.apps.filter(\.isPlaying)
        let playingIDs = Set(playing.map(\.id))
        var result = playing.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { row(id: $0.id, name: $0.displayName, playing: true) }
        result += recentApps.visibleIdle(excluding: playingIDs, at: Date())
            .map { row(id: $0.id, name: $0.name, playing: false) }
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
