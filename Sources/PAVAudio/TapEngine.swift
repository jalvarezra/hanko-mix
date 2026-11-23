import Foundation
import PAVCore

public enum TapStatus: Sendable, Equatable {
    case active
    case failed(String)
}

/// Reconciles the taps that should exist (`TapPlanner`) with the ones that do,
/// creating, updating in place or destroying through an `AudioBackend` (spec §8.3).
/// Not thread-safe: call every method from the same serial queue.
public final class TapEngine: @unchecked Sendable {
    private struct Session {
        var spec: TapSpec
        var tap: TapHandle
        var aggregate: AggregateHandle
        var chain: ProcessingChain
    }

    private let backend: AudioBackend
    private let uidPrefix: String
    private var sessions: [TapKind: Session] = [:]
    private var failures: [TapKind: (spec: TapSpec, message: String)] = [:]

    public init(backend: AudioBackend, uidPrefix: String = Identifiers.uidPrefix) {
        self.backend = backend
        self.uidPrefix = uidPrefix
    }

    public var activeKinds: Set<TapKind> { Set(sessions.keys) }

    public func reconcile(desired: [TapSpec], parameters: (TapKind) -> ChainParameters) {
        let desiredByKind = Dictionary(desired.map { ($0.kind, $0) }, uniquingKeysWith: { _, last in last })

        for (kind, session) in sessions where desiredByKind[kind] == nil {
            teardown(session)
            sessions[kind] = nil
        }
        for kind in failures.keys where desiredByKind[kind] == nil {
            failures[kind] = nil
        }

        for spec in desired {
            if var session = sessions[spec.kind] {
                if session.spec.structuralKey != spec.structuralKey {
                    teardown(session)
                    sessions[spec.kind] = nil
                    create(spec, parameters: parameters(spec.kind))
                } else if session.spec.processObjectIDs != spec.processObjectIDs {
                    do {
                        try backend.updateTap(session.tap, processObjectIDs: spec.processObjectIDs.sorted(), exclusive: spec.exclusive)
                        session.spec = spec
                        sessions[spec.kind] = session
                    } catch {
                        teardown(session)
                        sessions[spec.kind] = nil
                        failures[spec.kind] = (spec, "Could not update the audio tap: \(error)")
                    }
                }
            } else if let failure = failures[spec.kind], failure.spec.structuralKey == spec.structuralKey {
                continue   // don't retry in a loop until something changes
            } else {
                failures[spec.kind] = nil
                create(spec, parameters: parameters(spec.kind))
            }
        }
    }

    public func updateParameters(for kind: TapKind, _ p: ChainParameters) {
        sessions[kind]?.chain.update(p)
    }

    public func status(for kind: TapKind) -> TapStatus? {
        if sessions[kind] != nil { return .active }
        if let failure = failures[kind] { return .failed(failure.message) }
        return nil
    }

    public func shutdown() {
        for session in sessions.values { teardown(session) }
        sessions.removeAll()
        failures.removeAll()
    }

    public func cleanupStale() {
        backend.destroyStaleObjects(uidPrefix: uidPrefix)
    }

    private func create(_ spec: TapSpec, parameters: ChainParameters) {
        let deviceUID: String? = if case .rest(let uid) = spec.kind { uid } else { nil }
        let tap: TapHandle
        do {
            tap = try backend.createTap(processObjectIDs: spec.processObjectIDs.sorted(), exclusive: spec.exclusive,
                                        deviceUID: deviceUID, uid: Identifiers.tapUIDPrefix + UUID().uuidString)
        } catch {
            failures[spec.kind] = (spec, "Could not create the audio tap: \(error)")
            return
        }
        var aggregate: AggregateHandle?
        do {
            let agg = try backend.createAggregate(uid: Identifiers.aggregateUIDPrefix + UUID().uuidString,
                                                  outputDeviceUID: spec.outputDeviceUID, tap: tap)
            aggregate = agg
            let chain = ProcessingChain(channels: 2, maxFrames: 4096, sampleRate: spec.outputSampleRate)
            chain.update(parameters)
            try backend.startIO(agg, chain: chain)
            sessions[spec.kind] = Session(spec: spec, tap: tap, aggregate: agg, chain: chain)
        } catch {
            // The tap mutes the app, so destroy it last-but-surely: the app must never stay silent.
            if let aggregate {
                backend.stopIO(aggregate)
                backend.destroyAggregate(aggregate)
            }
            backend.destroyTap(tap)
            failures[spec.kind] = (spec, "Could not route the audio: \(error)")
        }
    }

    private func teardown(_ session: Session) {
        backend.stopIO(session.aggregate)
        backend.destroyAggregate(session.aggregate)
        backend.destroyTap(session.tap)
    }
}
