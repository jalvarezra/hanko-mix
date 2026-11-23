import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    let state: AppState
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { setLaunchAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Permission") {
                Text("Hanko Mix uses the \"System Audio Recording\" permission to capture each app's audio, change its volume and equalize it, and play it back on your output device. Audio never leaves your Mac and nothing is recorded to disk.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            state.setLaunchAtLogin(enabled)
            loginError = nil
        } catch {
            loginError = "Could not update the login item: \(error.localizedDescription)"
        }
    }
}
