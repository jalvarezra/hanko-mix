import PAVCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state.permissionNotice {
            case .explain:
                PermissionNotice(state: state)
                Divider()
            case .denied:
                PermissionDeniedNotice()
                Divider()
            case nil:
                EmptyView()
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
            }
            if let mic = state.defaultInput {
                MicrophoneSectionView(state: state, mic: mic)
                    .id(mic.uid)   // fresh slider state when the microphone changes
            }
            if let error = state.deviceError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if state.defaultDevice != nil || state.defaultInput != nil {
                Divider()
            }
            HStack {
                Button("Settings…") { SettingsWindowPresenter.open(openSettings) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 360)
    }
}

private struct PermissionDeniedNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Permission denied", systemImage: "exclamationmark.lock").font(.headline)
            Text("Hanko Mix can't change any app's volume without the \"System Audio Recording\" permission. Your apps keep playing normally.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

private struct PermissionNotice: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Permission needed", systemImage: "lock.shield").font(.headline)
            Text("To change an app's volume, Hanko Mix needs the \"System Audio Recording\" permission. macOS will ask you next. Audio never leaves your Mac.")
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
