import PAVCore
import SwiftUI

/// System microphone picker, gain slider and mute button.
struct MicrophoneSectionView: View {
    let state: AppState
    let mic: InputDevice
    /// Local value while dragging, so HAL round-trips don't make the slider jump.
    @State private var draft: Double?

    var body: some View {
        let muted = MicMuteStrategy.isMuted(mic)
        let canMute = mic.muteSettable || mic.volumeSettable
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").foregroundStyle(.secondary).frame(width: 20)
                Picker("Microphone", selection: Binding(get: { mic.uid }, set: { state.setSystemInput($0) })) {
                    ForEach(state.inputDevices, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("System microphone — what Zoom, Meet and other apps record")
            }
            HStack(spacing: 8) {
                Slider(value: Binding(get: { draft ?? Double(mic.volume ?? 0) },
                                      set: { draft = $0; state.setMicVolume(Float($0)) }),
                       in: 0...1,
                       onEditingChanged: { editing in if !editing { draft = nil } })
                    .controlSize(.small)
                    .disabled(!mic.volumeSettable)
                    .help(mic.volumeSettable ? "Microphone gain" : "This microphone doesn't support volume control")
                Text(mic.volume.map { "\(Int((Double($0) * 100).rounded()))%" } ?? "—")
                    .monospacedDigit()
                    .font(.caption)
                    .frame(width: 38, alignment: .trailing)
                Button { state.toggleMicMute() } label: {
                    Image(systemName: muted ? "mic.slash.fill" : "mic")
                        .foregroundStyle(muted ? .red : .primary)
                }
                .buttonStyle(.borderless)
                .disabled(!canMute)
                .help(canMute ? (muted ? "Unmute microphone" : "Mute microphone") : "This microphone can't be muted from here")
            }
            .padding(.leading, 26)
        }
    }
}
