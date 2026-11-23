import Testing
@testable import PAVCore

private let builtin = OutputDevice(uid: "builtin", name: "MacBook Speakers", transport: .builtIn, sampleRate: 48_000, channels: 2)
private let usb = OutputDevice(uid: "usb-dac", name: "USB DAC", transport: .usb, sampleRate: 48_000, channels: 2)
private let airpods = OutputDevice(uid: "airpods", name: "AirPods", transport: .bluetooth, sampleRate: 48_000, channels: 2)

private let spotifyID = AppID("com.spotify.client")
private let zoomID = AppID("us.zoom.xos")

private func spotify(playing: Bool = true) -> AppGroup {
    AppGroup(id: spotifyID, displayName: "Spotify", processObjectIDs: [11, 12], isPlaying: playing, outputDeviceUIDs: ["builtin"])
}
private func zoom() -> AppGroup {
    AppGroup(id: zoomID, displayName: "zoom.us", processObjectIDs: [21], isPlaying: true, outputDeviceUIDs: ["usb-dac"])
}
private func snapshot(_ apps: [AppGroup], devices: [OutputDevice] = [builtin, usb]) -> SystemSnapshot {
    SystemSnapshot(apps: apps, devices: devices, defaultOutputUID: "builtin")
}
private func settings(volume: Float = 1, output: String? = nil) -> AppSettings {
    var s = AppSettings(displayName: "x")
    s.volume = volume
    s.outputDeviceUID = output
    return s
}

@Test func untouchedAppAtDefaultsGetsNoTap() {
    #expect(TapPlanner.plan(snapshot: snapshot([spotify()]), appSettings: [:], deviceSettings: [:], keepAlive: []).isEmpty)
}

@Test func volumeChangeCreatesAppTap() {
    let plan = TapPlanner.plan(snapshot: snapshot([spotify()]), appSettings: [spotifyID: settings(volume: 0.8)], deviceSettings: [:], keepAlive: [])
    #expect(plan == [TapSpec(kind: .app(spotifyID), processObjectIDs: [11, 12], exclusive: false, outputDeviceUID: "builtin", outputSampleRate: 48_000)])
}

@Test func resetToDefaultsKeepsTapWhilePlaying() {
    let snap = snapshot([spotify()])
    let plan = TapPlanner.plan(snapshot: snap, appSettings: [spotifyID: settings(volume: 1)], deviceSettings: [:], keepAlive: [spotifyID])
    #expect(plan.count == 1)
    let stopped = snapshot([spotify(playing: false)])
    let keep = KeepAlive.next(current: [spotifyID], snapshot: stopped, plannedApps: [spotifyID])
    #expect(keep.isEmpty)
    #expect(TapPlanner.plan(snapshot: stopped, appSettings: [spotifyID: settings(volume: 1)], deviceSettings: [:], keepAlive: keep).isEmpty)
}

@Test func keepAliveAddsPlannedPlayingApps() {
    #expect(KeepAlive.next(current: [], snapshot: snapshot([spotify()]), plannedApps: [spotifyID]) == [spotifyID])
}

@Test func appKeepsItsOwnDeviceWhenOnlyVolumeChanges() {
    let plan = TapPlanner.plan(snapshot: snapshot([zoom()]), appSettings: [zoomID: settings(volume: 0.5)], deviceSettings: [:], keepAlive: [])
    #expect(plan.first?.outputDeviceUID == "usb-dac")
}

@Test func assignedDeviceMissingFallsBackToDefault() {
    let s = settings(volume: 1, output: "airpods")
    let snap = snapshot([spotify()])
    #expect(ProcessingRule.effectiveOutputUID(for: spotify(), settings: s, snapshot: snap) == "builtin")
    #expect(s.outputDeviceUID == "airpods")
}

@Test func assignedDeviceReturnsWhenReconnected() {
    let snap = snapshot([spotify()], devices: [builtin, usb, airpods])
    let s = settings(volume: 1, output: "airpods")
    #expect(ProcessingRule.effectiveOutputUID(for: spotify(), settings: s, snapshot: snap) == "airpods")
    #expect(ProcessingRule.needsProcessing(app: spotify(), settings: s, deviceSettings: [:], snapshot: snap))
}

@Test func deviceEQCreatesExclusiveRestTapExcludingTappedApps() {
    var eq = DeviceSettings()
    eq.eqEnabled = true
    eq.bands = [EQBand(type: .peaking, frequency: 1000, gainDB: 3, q: 1)]
    let plan = TapPlanner.plan(snapshot: snapshot([spotify(), zoom()]), appSettings: [spotifyID: settings(volume: 0.8)], deviceSettings: ["builtin": eq], keepAlive: [])
    #expect(plan.count == 2)
    let rest = plan.first { $0.kind == .rest(deviceUID: "builtin") }
    #expect(rest?.exclusive == true)
    #expect(rest?.processObjectIDs == [11, 12])
    #expect(plan.contains { $0.kind == .app(spotifyID) })
}

@Test func noRestTapForInactiveNonDefaultDevice() {
    var eq = DeviceSettings()
    eq.mono = true
    let plan = TapPlanner.plan(snapshot: snapshot([spotify()]), appSettings: [:], deviceSettings: ["usb-dac": eq], keepAlive: [])
    #expect(plan.isEmpty)
}

@Test func sampleRateChangeChangesStructuralKey() {
    let a = TapSpec(kind: .app(spotifyID), processObjectIDs: [1], exclusive: false, outputDeviceUID: "builtin", outputSampleRate: 48_000)
    var b = a
    b.outputSampleRate = 44_100
    #expect(a.structuralKey != b.structuralKey)
    var c = a
    c.processObjectIDs = [1, 2]
    #expect(a.structuralKey == c.structuralKey)
}

@Test func pausedAppWithLoweredVolumeKeepsItsTap() {
    let plan = TapPlanner.plan(snapshot: snapshot([spotify(playing: false)]), appSettings: [spotifyID: settings(volume: 0.2)], deviceSettings: [:], keepAlive: [])
    #expect(plan.map(\.kind) == [.app(spotifyID)])
}

@Test func deviceEQAloneDoesNotCreatePerAppTaps() {
    var eq = DeviceSettings()
    eq.mono = true
    let plan = TapPlanner.plan(snapshot: snapshot([spotify()]), appSettings: [:], deviceSettings: ["builtin": eq], keepAlive: [])
    #expect(plan.map(\.kind) == [.rest(deviceUID: "builtin")])
}

@Test func restTapAlwaysExcludesOwnProcess() {
    var eq = DeviceSettings()
    eq.mono = true
    var snap = snapshot([spotify()])
    snap.ownProcessObjectIDs = [99]
    let plan = TapPlanner.plan(snapshot: snap, appSettings: [:], deviceSettings: ["builtin": eq], keepAlive: [])
    #expect(plan.first?.processObjectIDs == [99])
}
