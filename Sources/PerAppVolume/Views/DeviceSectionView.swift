import PAVCore
import SwiftUI

struct DeviceSectionView: View {
    let state: AppState
    let device: OutputDevice

    var body: some View {
        let settings = state.deviceSettings(for: device.uid)
        VStack(alignment: .leading, spacing: 6) {
            Label(device.name, systemImage: "hifispeaker.fill").font(.callout.bold())
            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { settings.eqEnabled },
                                     set: { on in state.updateDeviceSettings(device.uid) { $0.eqEnabled = on } })) {
                    Text(settings.autoEQName.map { "EQ: \($0)" } ?? "EQ")
                        .lineLimit(1)
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
        }
    }
}
