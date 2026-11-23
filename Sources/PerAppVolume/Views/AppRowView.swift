import PAVCore
import SwiftUI

struct AppRowView: View {
    let state: AppState
    let row: AppRow

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon)
                } else {
                    Image(systemName: FriendlyNames.systemSymbol(for: row.id) ?? "app")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name).lineLimit(1)
                    if case .failed(let message) = row.status {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(message)
                    }
                }
                .font(.callout)
                Slider(value: Binding(get: { Double(row.volume) },
                                      set: { state.setVolume(Float($0), for: row.id) }),
                       in: Double(AppSettings.volumeRange.lowerBound)...Double(AppSettings.volumeRange.upperBound))
                    .controlSize(.small)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { state.resetVolume(for: row.id) })
                    .help("Double-click to reset to 100%")
            }

            Text(String(format: "%d%%", Int((row.volume * 100).rounded())))
                .monospacedDigit()
                .font(.caption)
                .frame(width: 38, alignment: .trailing)

            Button {
                state.setMuted(!row.muted, for: row.id)
            } label: {
                Image(systemName: row.muted ? "speaker.slash.fill" : "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help(row.muted ? "Unmute" : "Mute")

            Menu {
                Picker("Output", selection: Binding(get: { row.outputUID }, set: { state.setOutput($0, for: row.id) })) {
                    Text("Automatic (whatever the app uses)").tag(String?.none)
                    ForEach(state.selectableDevices, id: \.uid) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "hifispeaker")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Output device")
        }
    }
}
