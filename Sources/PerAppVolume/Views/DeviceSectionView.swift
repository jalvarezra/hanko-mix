import PAVCore
import SwiftUI

/// System output picker plus EQ/mono toggles for the selected device.
struct DeviceSectionView: View {
    let state: AppState
    let device: OutputDevice

    var body: some View {
        let settings = state.deviceSettings(for: device.uid)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hifispeaker.fill").foregroundStyle(.secondary).frame(width: 20)
                Picker("Output", selection: Binding(get: { device.uid }, set: { state.setSystemOutput($0) })) {
                    ForEach(state.systemOutputDevices, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("System output — where every app plays by default")
            }
            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { settings.eqEnabled },
                                     set: { on in state.updateDeviceSettings(device.uid) { $0.eqEnabled = on } })) {
                    Text(settings.autoEQName.map { "EQ: \($0)" } ?? "EQ").lineLimit(1)
                }
                .disabled(settings.bands.isEmpty && settings.preampDB == 0)
                .help(settings.bands.isEmpty ? "Set up an EQ in Settings" : "Toggle EQ")

                Toggle("Mono", isOn: Binding(get: { settings.mono },
                                             set: { on in state.updateDeviceSettings(device.uid) { $0.mono = on } }))
                Spacer()
                if settings.balance != 0 {
                    Text(settings.balance < 0 ? "Balance L \(Int(-settings.balance * 100))%" : "Balance R \(Int(settings.balance * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.leading, 26)
        }
    }
}
