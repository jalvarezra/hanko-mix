/// Fixed-capacity bank of biquad coefficients, stored inline (no heap) so it can be
/// handed to the real-time thread.
public struct CoefficientBank: Sendable {
    public static let capacity = DeviceSettings.maxBands
    private var storage: (BiquadCoefficients, BiquadCoefficients, BiquadCoefficients, BiquadCoefficients,
                          BiquadCoefficients, BiquadCoefficients, BiquadCoefficients, BiquadCoefficients,
                          BiquadCoefficients, BiquadCoefficients)
    public private(set) var count = 0

    public init() {
        let i = BiquadCoefficients.identity
        storage = (i, i, i, i, i, i, i, i, i, i)
    }

    public init(bands: [EQBand], sampleRate: Double) {
        self.init()
        for band in bands where band.enabled && count < Self.capacity {
            self[count] = BiquadCoefficients.make(band, sampleRate: sampleRate)
            count += 1
        }
    }

    public subscript(index: Int) -> BiquadCoefficients {
        get { withUnsafeBytes(of: storage) { $0.load(fromByteOffset: index * MemoryLayout<BiquadCoefficients>.stride, as: BiquadCoefficients.self) } }
        set { withUnsafeMutableBytes(of: &storage) { $0.storeBytes(of: newValue, toByteOffset: index * MemoryLayout<BiquadCoefficients>.stride, as: BiquadCoefficients.self) } }
    }
}

/// Runs a cascade of biquads (Direct Form II transposed) over interleaved audio,
/// keeping per-channel state in preallocated memory.
public final class EQChain: @unchecked Sendable {
    private let channels: Int
    private let state: UnsafeMutablePointer<Double>   // [band][channel][z1, z2]

    public init(channels: Int) {
        self.channels = channels
        let count = CoefficientBank.capacity * channels * 2
        state = .allocate(capacity: count)
        state.initialize(repeating: 0, count: count)
    }

    deinit { state.deallocate() }

    public func reset() {
        state.update(repeating: 0, count: CoefficientBank.capacity * channels * 2)
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frames: Int, bank: CoefficientBank) {
        for b in 0..<bank.count {
            let c = bank[b]
            for ch in 0..<channels {
                let z = state + (b * channels + ch) * 2
                var z1 = z[0], z2 = z[1]
                var i = ch
                for _ in 0..<frames {
                    let x = Double(buffer[i])
                    let y = c.b0 * x + z1
                    z1 = c.b1 * x - c.a1 * y + z2
                    z2 = c.b2 * x - c.a2 * y
                    buffer[i] = Float(y)
                    i += channels
                }
                z[0] = z1; z[1] = z2
            }
        }
    }
}
