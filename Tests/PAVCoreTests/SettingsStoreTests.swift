import Foundation
import Testing
@testable import PAVCore

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pav-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func settingsURL(_ dir: URL) -> URL { dir.appendingPathComponent("settings.json") }

@Test func missingFileLoadsDefaults() {
    let store = SettingsStore(directory: tempDir())
    #expect(store.load() == .fresh)
    #expect(store.file == SettingsFile())
}

@Test func roundTripPreservesSettings() throws {
    let dir = tempDir()
    let store = SettingsStore(directory: dir)
    _ = store.load()
    store.mutate { file in
        var app = AppSettings(displayName: "Spotify")
        app.volume = 0.4
        app.outputDeviceUID = "usb"
        file.apps["com.spotify.client"] = app
        var device = DeviceSettings()
        device.mono = true
        file.devices["builtin"] = device
    }
    try store.flush()
    let reloaded = SettingsStore(directory: dir)
    #expect(reloaded.load() == .loaded)
    #expect(reloaded.file == store.file)
}

@Test func corruptFileIsBackedUpAndDefaultsUsed() throws {
    let dir = tempDir()
    try Data("{nope".utf8).write(to: settingsURL(dir))
    let store = SettingsStore(directory: dir)
    guard case .recoveredFromCorrupt(let backup) = store.load() else { Issue.record("expected recovery"); return }
    #expect(FileManager.default.fileExists(atPath: backup.path))
    #expect(backup.lastPathComponent.hasPrefix("settings.corrupt-"))
    #expect(store.file == SettingsFile())
}

@Test func emptyFileTreatedAsCorrupt() throws {
    let dir = tempDir()
    try Data().write(to: settingsURL(dir))
    guard case .recoveredFromCorrupt = SettingsStore(directory: dir).load() else { Issue.record("expected recovery"); return }
}

@Test func newerVersionIsNotOverwritten() throws {
    let dir = tempDir()
    let original = Data(#"{"version": 99}"#.utf8)
    try original.write(to: settingsURL(dir))
    let store = SettingsStore(directory: dir)
    #expect(store.load() == .newerVersion(99))
    #expect(store.isReadOnly)
    store.mutate { $0.launchAtLogin = true }
    try store.flush()
    #expect(try Data(contentsOf: settingsURL(dir)) == original)
    #expect(store.file.launchAtLogin)   // still applied in memory
}

@Test func moreThanTenBandsAreTruncated() throws {
    let dir = tempDir()
    let band = #"{"type":"peaking","frequency":1000,"gainDB":1,"q":1,"enabled":true}"#
    let json = #"{"version":1,"apps":{},"devices":{"builtin":{"eqEnabled":true,"bands":["# + Array(repeating: band, count: 12).joined(separator: ",") + "]}}}"
    try Data(json.utf8).write(to: settingsURL(dir))
    let store = SettingsStore(directory: dir)
    #expect(store.load() == .loaded)
    #expect(store.file.devices["builtin"]?.bands.count == 10)
}
