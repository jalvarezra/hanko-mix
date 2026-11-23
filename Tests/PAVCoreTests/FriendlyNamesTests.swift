import Testing
@testable import PAVCore

@Test func knownSystemProcessesGetFriendlyNames() {
    #expect(FriendlyNames.displayName(for: AppID("systemsoundserverd"), fallback: "systemsoundserverd") == "System Sounds")
    #expect(FriendlyNames.displayName(for: AppID("com.apple.PowerChime"), fallback: "PowerChime") == "Power Chime")
    #expect(FriendlyNames.displayName(for: AppID("com.apple.accessibility.heard"), fallback: "com.apple.accessibility.heard") == "Background Sounds")
}

@Test func bundleIDNamesBecomeReadable() {
    #expect(FriendlyNames.displayName(for: AppID("com.apple.SiriSetup.SiriSetupSettingsIntents"),
                                      fallback: "com.apple.SiriSetup.SiriSetupSettingsIntents") == "Siri Setup Settings Intents")
    #expect(FriendlyNames.displayName(for: AppID("com.apple.mediaanalysisd"), fallback: "com.apple.mediaanalysisd") == "Mediaanalysisd")
}

@Test func executablePathsUseTheirFileName() {
    #expect(FriendlyNames.displayName(for: AppID("/usr/libexec/PerfPowerServices"), fallback: "PerfPowerServices") == "Perf Power Services")
}

@Test func realAppNamesAreKept() {
    #expect(FriendlyNames.displayName(for: AppID("com.spotify.client"), fallback: "Spotify") == "Spotify")
    #expect(FriendlyNames.displayName(for: AppID("com.google.Chrome"), fallback: "Google Chrome") == "Google Chrome")
}

@Test func invisibleCharactersAreTrimmed() {
    #expect(FriendlyNames.displayName(for: AppID("net.whatsapp.WhatsApp"), fallback: "\u{200E}WhatsApp") == "WhatsApp")
}

@Test func systemSoundsHaveASymbol() {
    #expect(FriendlyNames.systemSymbol(for: AppID("systemsoundserverd")) == "bell.fill")
    #expect(FriendlyNames.systemSymbol(for: AppID("com.spotify.client")) == nil)
}

@Test func grouperAppliesFriendlyNames() {
    struct NoBundles: ProcessResolving {
        func responsiblePID(for pid: Int32) -> Int32? { nil }
        func executablePath(for pid: Int32) -> String? { nil }
        func bundleInfo(forExecutablePath path: String) -> (bundleID: String, name: String)? { nil }
    }
    let groups = AppGrouper.group([AudioProcessInfo(objectID: 1, pid: 10, bundleID: "systemsoundserverd", executablePath: nil,
                                                    isRunningOutput: true, outputDeviceUIDs: [])], ownPID: 1, resolver: NoBundles())
    #expect(groups.first?.displayName == "System Sounds")
}
