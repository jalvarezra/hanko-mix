import SwiftUI

struct SettingsView: View {
    let state: AppState

    var body: some View {
        TabView {
            DeviceSettingsView(state: state)
                .tabItem { Label("Devices", systemImage: "hifispeaker.2") }
            AppsSettingsView(state: state)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            GeneralSettingsView(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 520)
    }
}
