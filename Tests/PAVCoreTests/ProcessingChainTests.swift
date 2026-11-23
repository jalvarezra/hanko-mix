import Foundation
import Testing
@testable import PAVCore

private func stereoSine(amplitude: Float, frames: Int = 4800) -> [Float] {
    (0..<frames).flatMap { i -> [Float] in
        let v = amplitude * Float(sin(2 * Double.pi * 1000 * Double(i) / 48_000))
        return [v, v]
    }
}

private func run(_ chain: ProcessingChain, _ input: [Float]) -> [Float] {
    var output = [Float](repeating: 0, count: input.count)
    input.withUnsafeBufferPointer { inp in
        output.withUnsafeMutableBufferPointer { out in
            chain.process(input: inp.baseAddress!, output: out.baseAddress!, frames: input.count / 2)
        }
    }
    return output
}

@Test func chainAtUnityIsBitTransparent() {
    let chain = ProcessingChain(channels: 2, maxFrames: 4800, sampleRate: 48_000)
    chain.update(ChainParameters(gain: 1, muted: false, device: DeviceSettings(), sampleRate: 48_000))
    let input = stereoSine(amplitude: 0.8)
    #expect(run(chain, input) == input)
}

@Test func chainMutedOutputsSilenceAfterRamp() {
    let chain = ProcessingChain(channels: 2, maxFrames: 4800, sampleRate: 48_000)
    chain.update(ChainParameters(gain: 1, muted: true, device: DeviceSettings(), sampleRate: 48_000))
    _ = run(chain, stereoSine(amplitude: 0.8))   // ramp happens here
    #expect(run(chain, stereoSine(amplitude: 0.8)).allSatisfy { $0 == 0 })
}

@Test func chain200PercentNeverClips() {
    let chain = ProcessingChain(channels: 2, maxFrames: 4800, sampleRate: 48_000)
    chain.update(ChainParameters(gain: 2, muted: false, device: DeviceSettings(), sampleRate: 48_000))
    _ = run(chain, stereoSine(amplitude: 1.0))
    #expect(run(chain, stereoSine(amplitude: 1.0)).allSatisfy { abs($0) <= 1.0 })
}

@Test func chainAppliesDeviceEQ() {
    var device = DeviceSettings()
    device.eqEnabled = true
    device.bands = [EQBand(type: .peaking, frequency: 1000, gainDB: -12, q: 1)]
    let chain = ProcessingChain(channels: 2, maxFrames: 4800, sampleRate: 48_000)
    chain.update(ChainParameters(gain: 1, muted: false, device: device, sampleRate: 48_000))
    _ = run(chain, stereoSine(amplitude: 0.5))
    let peak = run(chain, stereoSine(amplitude: 0.5)).map { abs($0) }.max()!
    #expect(peak < 0.5 * 0.3)   // -12 dB ≈ 0.25
}
