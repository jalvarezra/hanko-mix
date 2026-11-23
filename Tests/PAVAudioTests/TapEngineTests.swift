import Testing
import PAVCore
@testable import PAVAudio

final class FakeAudioBackend: AudioBackend {
    enum Call: Equatable { case createTap, updateTap, destroyTap, createAggregate, startIO, stopIO, destroyAggregate, destroyStale }
    struct Failure: Error {}

    var calls: [Call] = []
    var failOn: Set<Call> = []
    var lastCreateTapDeviceUID: String??
    private var nextID: UInt32 = 1

    private func record(_ call: Call) throws {
        calls.append(call)
        if failOn.contains(call) { throw Failure() }
    }

    func createTap(processObjectIDs: [UInt32], exclusive: Bool, deviceUID: String?, uid: String) throws -> TapHandle {
        lastCreateTapDeviceUID = .some(deviceUID)
        try record(.createTap)
        nextID += 1
        return TapHandle(tapID: nextID, uid: "tap-\(nextID)")
    }
    func updateTap(_ tap: TapHandle, processObjectIDs: [UInt32], exclusive: Bool) throws { try record(.updateTap) }
    func destroyTap(_ tap: TapHandle) { calls.append(.destroyTap) }
    func createAggregate(uid: String, outputDeviceUID: String, tap: TapHandle) throws -> AggregateHandle {
        try record(.createAggregate)
        nextID += 1
        return AggregateHandle(deviceID: nextID, uid: uid)
    }
    func startIO(_ agg: AggregateHandle, chain: ProcessingChain) throws { try record(.startIO) }
    func stopIO(_ agg: AggregateHandle) { calls.append(.stopIO) }
    func destroyAggregate(_ agg: AggregateHandle) { calls.append(.destroyAggregate) }
    func destroyStaleObjects(uidPrefix: String) { calls.append(.destroyStale) }
}

private let spotify = AppID("com.spotify.client")

private func spec(_ ids: Set<UInt32> = [1, 2], output: String = "builtin", kind: TapKind = .app(spotify)) -> TapSpec {
    TapSpec(kind: kind, processObjectIDs: ids, exclusive: kind != .app(spotify), outputDeviceUID: output, outputSampleRate: 48_000)
}

private let params: @Sendable (TapKind) -> ChainParameters = { _ in
    ChainParameters(gain: 0.5, muted: false, device: DeviceSettings(), sampleRate: 48_000)
}

@Test func createsTapAggregateAndStartsIOForNewSpec() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    #expect(backend.calls == [.createTap, .createAggregate, .startIO])
    #expect(engine.status(for: .app(spotify)) == .active)
    #expect(backend.lastCreateTapDeviceUID == .some(nil))
}

@Test func restTapIsBoundToItsDevice() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec([], kind: .rest(deviceUID: "builtin"))], parameters: params)
    #expect(backend.lastCreateTapDeviceUID == .some("builtin"))
}

@Test func removesSessionNoLongerDesired() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    backend.calls = []
    engine.reconcile(desired: [], parameters: params)
    #expect(backend.calls == [.stopIO, .destroyAggregate, .destroyTap])
    #expect(engine.status(for: .app(spotify)) == nil)
}

@Test func processSetChangeUpdatesInsteadOfRecreating() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec([1, 2])], parameters: params)
    backend.calls = []
    engine.reconcile(desired: [spec([1, 2, 3])], parameters: params)
    #expect(backend.calls == [.updateTap])
}

@Test func deviceChangeRecreates() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec(output: "builtin")], parameters: params)
    backend.calls = []
    engine.reconcile(desired: [spec(output: "usb")], parameters: params)
    #expect(backend.calls == [.stopIO, .destroyAggregate, .destroyTap, .createTap, .createAggregate, .startIO])
}

@Test func aggregateFailureDestroysTapImmediatelyAndMarksFailed() {
    let backend = FakeAudioBackend()
    backend.failOn = [.createAggregate]
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    #expect(backend.calls == [.createTap, .createAggregate, .destroyTap])
    guard case .failed = engine.status(for: .app(spotify)) else { Issue.record("expected failed"); return }
}

@Test func startIOFailureUnwindsEverything() {
    let backend = FakeAudioBackend()
    backend.failOn = [.startIO]
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    #expect(backend.calls == [.createTap, .createAggregate, .startIO, .stopIO, .destroyAggregate, .destroyTap])
    guard case .failed = engine.status(for: .app(spotify)) else { Issue.record("expected failed"); return }
}

@Test func failedSpecIsNotRetriedUntilItChanges() {
    let backend = FakeAudioBackend()
    backend.failOn = [.createAggregate]
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    backend.calls = []
    engine.reconcile(desired: [spec()], parameters: params)
    #expect(backend.calls.isEmpty)
    backend.failOn = []
    engine.reconcile(desired: [spec(output: "usb")], parameters: params)
    #expect(backend.calls == [.createTap, .createAggregate, .startIO])
    #expect(engine.status(for: .app(spotify)) == .active)
}

@Test func parameterUpdateDoesNotTouchBackend() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    backend.calls = []
    engine.updateParameters(for: .app(spotify), ChainParameters(gain: 1.5, muted: false, device: DeviceSettings(), sampleRate: 48_000))
    #expect(backend.calls.isEmpty)
}

@Test func shutdownTearsDownEverything() {
    let backend = FakeAudioBackend()
    let engine = TapEngine(backend: backend)
    engine.reconcile(desired: [spec()], parameters: params)
    backend.calls = []
    engine.shutdown()
    #expect(backend.calls == [.stopIO, .destroyAggregate, .destroyTap])
}
