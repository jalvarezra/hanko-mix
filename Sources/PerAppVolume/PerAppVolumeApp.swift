import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var state: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Self.state?.shutdown() }
    }
}

@main
struct PerAppVolumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state: AppState

    init() {
        let state = AppState.live()
        AppDelegate.state = state
        state.start()
        _state = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra("PerAppVolume", systemImage: "speaker.wave.2") {
            MenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}
