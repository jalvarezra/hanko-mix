import PAVCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.needsPermissionExplanation {
                PermissionNotice(state: state)
                Divider()
            }
            if state.rows.isEmpty {
                Text("No app is playing audio right now.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(state.rows) { row in
                    AppRowView(state: state, row: row)
                        .opacity(row.isPlaying ? 1 : 0.5)
                }
            }
            Divider()
            if let device = state.defaultDevice {
                DeviceSectionView(state: state, device: device)
                Divider()
            }
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 360)
    }
}

private struct PermissionNotice: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Permission needed", systemImage: "lock.shield").font(.headline)
            Text("To change an app's volume, PerAppVolume needs the \"System Audio Recording\" permission. macOS will ask you next. Audio never leaves your Mac.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not now") { state.deferPermissionExplanation() }
                Button("Continue") { state.acceptPermissionExplanation() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
