import Foundation
import Testing
@testable import PAVCore

private func sine(amplitude: Float, count: Int = 4800) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2 * Double.pi * 1000 * Double($0) / 48_000)) }
}

@Test func limiterNeverExceedsFullScaleAt200Percent() {
    var buf = sine(amplitude: 1.0).map { $0 * 2.0 }
    let limiter = SoftLimiter()
    buf.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, count: $0.count) }
    #expect(buf.map { abs($0) }.max()! <= 1.0)
}

@Test func limiterIsTransparentBelowThreshold() {
    let input = sine(amplitude: 0.5)
    var buf = input
    let limiter = SoftLimiter()
    buf.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, count: $0.count) }
    for i in 0..<buf.count { #expect(abs(buf[i] - input[i]) < 1e-6) }
}
