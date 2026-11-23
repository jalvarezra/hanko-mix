import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var state: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Self.state?.shutdown() }
    }
}

@main
struct HankoMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state: AppState

    init() {
        let state = AppState.live()
        AppDelegate.state = state
        state.start()
        _state = State(initialValue: state)
    }

    /// Monochrome template image (adapts to light/dark menu bars); nil under `swift run`.
    private static let menuBarIcon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        // 18 pt tall, keeping the artwork's proportions (the ears make it wider).
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: (18 * aspect).rounded(), height: 18)
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "speaker.wave.2")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}
