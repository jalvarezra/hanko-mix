import Foundation
import PAVAudio
import PAVCore

/// Owns the audio side (planner + engine + keep-alive) on one serial queue.
final class AudioCoordinator: @unchecked Sendable {
    struct Result: Sendable {
        var statuses: [TapKind: TapStatus]
        var plannedCount: Int
    }

    let queue = DispatchQueue(label: "io.github.perappvolume.audio", qos: .userInteractive)
    private let engine: TapEngine
    private var keepAlive: Set<AppID> = []

    init(backend: AudioBackend) {
        engine = TapEngine(backend: backend)
    }

    func cleanupStale() {
        queue.async { self.engine.cleanupStale() }
    }

    func shutdown() {
        queue.sync { self.engine.shutdown() }
    }

    /// Plans, reconciles and pushes fresh parameters to every live tap.
    /// Unchanged specs cause no backend calls, so this is cheap enough for slider drags.
    func apply(snapshot: SystemSnapshot, appSettings: [AppID: AppSettings], deviceSettings: [String: DeviceSettings],
               allowTaps: Bool, completion: @escaping @Sendable (Result) -> Void) {
        queue.async { [self] in
            let planned = TapPlanner.plan(snapshot: snapshot, appSettings: appSettings,
                                          deviceSettings: deviceSettings, keepAlive: keepAlive)
            let desired = allowTaps ? planned : []
            let plannedApps = Set(desired.compactMap { spec -> AppID? in
                if case .app(let id) = spec.kind { id } else { nil }
            })
            keepAlive = KeepAlive.next(current: keepAlive, snapshot: snapshot, plannedApps: plannedApps)

            let specs = Dictionary(desired.map { ($0.kind, $0) }, uniquingKeysWith: { _, last in last })
            let parameters: (TapKind) -> ChainParameters = { kind in
                Self.parameters(for: kind, spec: specs[kind], appSettings: appSettings, deviceSettings: deviceSettings)
            }
            engine.reconcile(desired: desired, parameters: parameters)
            for kind in specs.keys { engine.updateParameters(for: kind, parameters(kind)) }

            var statuses: [TapKind: TapStatus] = [:]
            for kind in specs.keys { statuses[kind] = engine.status(for: kind) }
            completion(Result(statuses: statuses, plannedCount: planned.count))
        }
    }

    static func parameters(for kind: TapKind, spec: TapSpec?, appSettings: [AppID: AppSettings],
                           deviceSettings: [String: DeviceSettings]) -> ChainParameters {
        let outputUID = spec?.outputDeviceUID ?? ""
        let device = deviceSettings[outputUID] ?? DeviceSettings()
        let sampleRate = spec?.outputSampleRate ?? 48_000
        switch kind {
        case .app(let id):
            let s = appSettings[id]
            return ChainParameters(gain: s?.volume ?? 1, muted: s?.muted ?? false, device: device, sampleRate: sampleRate)
        case .rest:
            return ChainParameters(gain: 1, muted: false, device: device, sampleRate: sampleRate)
        }
    }
}
