import PAVCore
import SwiftUI

struct AppsSettingsView: View {
    let state: AppState

    var body: some View {
        let apps = state.settings.apps.map { RememberedApp(id: $0.key, value: $0.value) }
            .sorted { $0.value.displayName.localizedCaseInsensitiveCompare($1.value.displayName) == .orderedAscending }
        Group {
            if apps.isEmpty {
                Text("Apps you play audio from will appear here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(apps, columns: {
                    TableColumn("App") { Text($0.value.displayName) }
                    TableColumn("Volume") { Text("\(Int(($0.value.volume * 100).rounded()))%\($0.value.muted ? " (muted)" : "")") }
                        .width(90)
                    TableColumn("Output") { item in
                        Text(item.value.outputDeviceUID.map { state.device(uid: $0)?.name ?? $0 } ?? "Automatic")
                    }
                    TableColumn("Last played") { item in
                        Text(item.value.lastSeen.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                    }
                    .width(110)
                    TableColumn("") { item in
                        Button("Forget") { state.forgetApp(AppID(item.id)) }
                    }
                    .width(70)
                })
            }
        }
        .padding()
    }
}

private struct RememberedApp: Identifiable {
    let id: String
    let value: AppSettings
}
