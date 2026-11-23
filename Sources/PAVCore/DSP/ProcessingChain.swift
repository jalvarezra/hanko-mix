import Foundation

public struct ChainParameters: Sendable, Equatable {
    public var gain: Float
    public var muted: Bool
    public var device: DeviceSettings
    public var sampleRate: Double

    public init(gain: Float, muted: Bool, device: DeviceSettings, sampleRate: Double) {
        self.gain = gain
        self.muted = muted
        self.device = device
        self.sampleRate = sampleRate
    }
}

/// Precomputed, heap-free parameters handed to the real-time thread.
struct PreparedParameters: Sendable {
    var version: UInt64 = 0
    var targetGain: Float = 1
    var deviceActive = false
    var eqEnabled = false
    var preamp: Float = 1
    var bank = CoefficientBank()
    var balance: Float = 0
    var mono = false
    var limiterEnabled = false
}

/// Per-tap processing: gain ramp → preamp + EQ → balance/mono → soft limiter.
/// `update` runs on any non-real-time thread; `process` only on the audio thread.
public final class ProcessingChain: @unchecked Sendable {
    private let channels: Int
    private let slot = ParameterSlot(PreparedParameters())
    private var nextVersion: UInt64 = 1        // writer-owned
    private var appliedVersion: UInt64 = 0     // reader-owned
    private var ramp: GainRamp
    private let eq: EQChain
    private let limiter = SoftLimiter()

    public init(channels: Int, maxFrames: Int, sampleRate: Double) {
        self.channels = channels
        ramp = GainRamp(sampleRate: sampleRate)
        eq = EQChain(channels: channels)
    }

    public func update(_ p: ChainParameters) {
        var prepared = PreparedParameters()
        prepared.version = nextVersion
        nextVersion += 1
        prepared.targetGain = p.muted ? 0 : p.gain
        prepared.deviceActive = p.device.isActive
        prepared.eqEnabled = p.device.eqEnabled
        prepared.preamp = pow(10, p.device.preampDB / 20)
        prepared.bank = CoefficientBank(bands: p.device.bands, sampleRate: p.sampleRate)
        prepared.balance = p.device.balance
        prepared.mono = p.device.mono && channels == 2
        let maxBandGain = p.device.bands.filter(\.enabled).map(\.gainDB).max() ?? 0
        prepared.limiterEnabled = prepared.targetGain > 1
            || (p.device.eqEnabled && p.device.preampDB + max(0, maxBandGain) > 0)
        slot.publish(prepared)
    }

    public func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frames: Int) {
        let p = slot.consumeLatest()
        if p.version != appliedVersion {
            appliedVersion = p.version
            ramp.setTarget(p.targetGain)
        }
        let samples = frames * channels
        output.update(from: input, count: samples)
        // Transparent bypass: unity gain, nothing active, ramp settled.
        if !p.deviceActive && ramp.isSettled && ramp.current == 1 { return }

        ramp.apply(to: output, frames: frames, channels: channels)
        if p.eqEnabled {
            if p.preamp != 1 {
                for i in 0..<samples { output[i] *= p.preamp }
            }
            eq.process(output, frames: frames, bank: p.bank)
        }
        if channels == 2 && (p.balance != 0 || p.mono) {
            BalanceMono.apply(output, frames: frames, balance: p.balance, mono: p.mono)
        }
        if p.limiterEnabled || ramp.current > 1 {
            limiter.process(output, count: samples)
        }
    }
}
