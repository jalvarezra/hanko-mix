import Testing
@testable import PAVCore

@Test func rampReachesTargetAfter20ms() {
    var r = GainRamp(sampleRate: 48_000, initial: 1.0)
    r.setTarget(0.5)
    var buf = [Float](repeating: 1, count: 960 * 2)
    buf.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 2) }
    #expect(abs(buf[buf.count - 1] - 0.5) < 1e-4)
    #expect(r.isSettled)
}

@Test func rampHasNoJumpsBiggerThanStep() {
    var r = GainRamp(sampleRate: 48_000, initial: 1.0)
    r.setTarget(0)
    var buf = [Float](repeating: 1, count: 960)
    buf.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 1) }
    for i in 1..<buf.count { #expect(abs(buf[i] - buf[i - 1]) <= 1.0 / 960 + 1e-6) }
}

@Test func zeroGainGivesExactZerosAfterRamp() {
    var r = GainRamp(sampleRate: 48_000, initial: 1.0)
    r.setTarget(0)
    var first = [Float](repeating: 1, count: 960)
    first.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 1) }
    var second = [Float](repeating: 1, count: 960)
    second.withUnsafeMutableBufferPointer { r.apply(to: $0.baseAddress!, frames: 960, channels: 1) }
    #expect(second.allSatisfy { $0 == 0.0 })
}
