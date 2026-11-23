import Testing
@testable import PAVCore

private struct FakeResolver: ProcessResolving {
    var responsible: [Int32: Int32] = [:]
    var bundles: [String: (String, String)] = [:]   // .app path → (bundleID, name)
    var executableOfPID: [Int32: String] = [:]

    func responsiblePID(for pid: Int32) -> Int32? { responsible[pid] }
    func executablePath(for pid: Int32) -> String? { executableOfPID[pid] }
    func bundleInfo(forExecutablePath path: String) -> (bundleID: String, name: String)? {
        bundles.first { path.hasPrefix($0.key + "/") }.map { (bundleID: $0.value.0, name: $0.value.1) }
    }
}

private let chromeApp = "/Applications/Google Chrome.app"
private let helper = chromeApp + "/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

private func proc(_ id: UInt32, pid: Int32, bundle: String?, path: String?, playing: Bool = false, devices: [String] = []) -> AudioProcessInfo {
    AudioProcessInfo(objectID: id, pid: pid, bundleID: bundle, executablePath: path, isRunningOutput: playing, outputDeviceUIDs: devices)
}

@Test func chromeHelpersCollapseIntoChrome() {
    let resolver = FakeResolver(bundles: [chromeApp: ("com.google.Chrome", "Google Chrome")])
    let groups = AppGrouper.group([
        proc(1, pid: 100, bundle: "com.google.Chrome", path: chromeApp + "/Contents/MacOS/Google Chrome"),
        proc(2, pid: 101, bundle: "com.google.Chrome.helper.renderer", path: helper, playing: true, devices: ["builtin"]),
        proc(3, pid: 102, bundle: "com.google.Chrome.helper.renderer", path: helper),
    ], ownPID: 1, resolver: resolver)
    #expect(groups.count == 1)
    #expect(groups.first?.id == AppID("com.google.Chrome"))
    #expect(groups.first?.displayName == "Google Chrome")
    #expect(groups.first?.processObjectIDs == [1, 2, 3])
}

@Test func xpcServiceGroupsUnderResponsibleApp() {
    let safariApp = "/Applications/Safari.app"
    let webkitGPU = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
    let resolver = FakeResolver(responsible: [300: 200],
                                bundles: [safariApp: ("com.apple.Safari", "Safari")],
                                executableOfPID: [200: safariApp + "/Contents/MacOS/Safari"])
    let groups = AppGrouper.group([proc(5, pid: 300, bundle: "com.apple.WebKit.GPU", path: webkitGPU, playing: true)], ownPID: 1, resolver: resolver)
    #expect(groups.map(\.id) == [AppID("com.apple.Safari")])
}

@Test func ownProcessIsExcluded() {
    let groups = AppGrouper.group([proc(9, pid: 42, bundle: "io.github.perappvolume", path: "/Applications/PerAppVolume.app/Contents/MacOS/PerAppVolume")],
                                  ownPID: 42, resolver: FakeResolver())
    #expect(groups.isEmpty)
}

@Test func processWithoutBundleOrPathIsExcluded() {
    #expect(AppGrouper.group([proc(9, pid: 50, bundle: nil, path: nil)], ownPID: 1, resolver: FakeResolver()).isEmpty)
}

@Test func isPlayingIsTrueIfAnyProcessPlays() {
    let resolver = FakeResolver(bundles: [chromeApp: ("com.google.Chrome", "Google Chrome")])
    let groups = AppGrouper.group([
        proc(1, pid: 100, bundle: "com.google.Chrome", path: chromeApp + "/Contents/MacOS/Google Chrome", devices: ["usb"]),
        proc(2, pid: 101, bundle: nil, path: helper, playing: true, devices: ["builtin", "usb"]),
    ], ownPID: 1, resolver: resolver)
    #expect(groups.first?.isPlaying == true)
    #expect(groups.first?.outputDeviceUIDs == ["usb", "builtin"])
}
