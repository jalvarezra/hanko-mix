import AppKit
import SwiftUI

/// Opens the Settings window in front, on the screen under the mouse.
/// A menu bar (LSUIElement) app isn't activated by `SettingsLink`, so its Settings
/// window would open behind the frontmost app, possibly on another display.
@MainActor
enum SettingsWindowPresenter {
    private static let swiftUISettingsIdentifier = "com_apple_SwiftUI_Settings_window"

    static func open(_ openSettings: OpenSettingsAction) {
        NSApp.activate()
        openSettings()
        // The window exists only after SwiftUI processes the action.
        DispatchQueue.main.async { bringToFront() }
    }

    private static func bringToFront() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == swiftUISettingsIdentifier }) else { return }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           window.screen != screen {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                          y: visible.midY - window.frame.height / 2))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
