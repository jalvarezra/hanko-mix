import PAVCore
import SwiftUI

/// Loads the bundled AutoEQ index without `Bundle.module` (whose accessor looks
/// outside Contents/ in an .app and traps when the bundle is missing).
enum BundledAutoEQ {
    static let catalog: AutoEQCatalog? = {
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        guard let url = AutoEQCatalog.locate(bundleName: "PerAppVolume_PerAppVolume.bundle", searchRoots: roots) else { return nil }
        return try? AutoEQCatalog.loadBundled(from: url)
    }()
}

struct DeviceSettingsView: View {
    let state: AppState
    @State private var selectedUID: String?
    @State private var query = ""

    private var deviceUID: String? { selectedUID ?? state.defaultDevice?.uid ?? state.allOutputDevices.first?.uid }

    var body: some View {
        Form {
            Picker("Device", selection: Binding(get: { deviceUID }, set: { selectedUID = $0 })) {
                ForEach(state.allOutputDevices, id: \.uid) { Text($0.name).tag(Optional($0.uid)) }
            }
            if let uid = deviceUID {
                deviceForm(uid: uid, settings: state.deviceSettings(for: uid))
            } else {
                Text("No output devices found.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func deviceForm(uid: String, settings: DeviceSettings) -> some View {
        Section("Equalizer") {
            Toggle("Enable EQ", isOn: binding(uid, \.eqEnabled))
            if let name = settings.autoEQName {
                LabeledContent("AutoEQ preset", value: name)
            }
            LabeledContent("Preamp") {
                HStack {
                    Slider(value: floatBinding(uid, \.preampDB), in: -20...6)
                    Text(String(format: "%+.1f dB", settings.preampDB)).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            ForEach(settings.bands.indices, id: \.self) { index in
                BandEditor(band: Binding(
                    get: { state.deviceSettings(for: uid).bands[safe: index] ?? settings.bands[index] },
                    set: { newBand in state.updateDeviceSettings(uid) { if $0.bands.indices.contains(index) { $0.bands[index] = newBand; $0.autoEQName = nil } } }
                ), onDelete: {
                    state.updateDeviceSettings(uid) { if $0.bands.indices.contains(index) { $0.bands.remove(at: index); $0.autoEQName = nil } }
                })
            }
            Button("Add band") {
                state.updateDeviceSettings(uid) { $0.bands.append(EQBand(type: .peaking, frequency: 1000, gainDB: 0, q: 1)) }
            }
            .disabled(settings.bands.count >= DeviceSettings.maxBands)
        }

        Section("AutoEQ headphone presets") {
            if let catalog = BundledAutoEQ.catalog {
                TextField("Search headphones (e.g. HD 650)", text: $query)
                ForEach(catalog.search(query, limit: 8), id: \.self) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            Text("\(entry.form) · \(entry.source)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apply") {
                            state.updateDeviceSettings(uid) {
                                $0.preampDB = entry.preampDB
                                $0.bands = entry.bands
                                $0.autoEQName = entry.name
                                $0.eqEnabled = true
                            }
                        }
                    }
                }
            } else {
                Text("The AutoEQ catalog is not available in this build.").foregroundStyle(.secondary)
            }
        }

        Section("Channels") {
            LabeledContent("Balance") {
                HStack {
                    Text("L").font(.caption)
                    Slider(value: Binding(get: { Double(state.deviceSettings(for: uid).balance) },
                                          set: { value in state.updateDeviceSettings(uid) { $0.balance = Snap.balance(Float(value)) } }),
                           in: -1...1)
                    Text("R").font(.caption)
                    Button("Center") { state.updateDeviceSettings(uid) { $0.balance = 0 } }
                        .disabled(settings.balance == 0)
                }
            }
            Toggle("Mono", isOn: binding(uid, \.mono))
        }
    }

    private func binding(_ uid: String, _ keyPath: WritableKeyPath<DeviceSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.deviceSettings(for: uid)[keyPath: keyPath] },
                set: { value in state.updateDeviceSettings(uid) { $0[keyPath: keyPath] = value } })
    }

    private func floatBinding(_ uid: String, _ keyPath: WritableKeyPath<DeviceSettings, Float>) -> Binding<Double> {
        Binding(get: { Double(state.deviceSettings(for: uid)[keyPath: keyPath]) },
                set: { value in state.updateDeviceSettings(uid) { $0[keyPath: keyPath] = Float(value) } })
    }
}

private struct BandEditor: View {
    @Binding var band: EQBand
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $band.enabled).labelsHidden()
            Picker("", selection: $band.type) {
                Text("Peak").tag(FilterType.peaking)
                Text("Low shelf").tag(FilterType.lowShelf)
                Text("High shelf").tag(FilterType.highShelf)
            }
            .labelsHidden()
            .frame(width: 100)
            field("Hz", value: $band.frequency, range: 20...20_000)
            field("dB", value: $band.gainDB, range: -20...20)
            field("Q", value: $band.q, range: 0.1...10)
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove band")
        }
    }

    private func field(_ unit: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 2) {
            TextField(unit, value: Binding(get: { value.wrappedValue },
                                           set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.precision(.fractionLength(0...2)))
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
