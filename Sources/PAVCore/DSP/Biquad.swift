import Foundation

/// Normalized biquad coefficients (a0 == 1), from the RBJ Audio EQ Cookbook.
public struct BiquadCoefficients: Sendable, Equatable {
    public var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    public static func make(_ band: EQBand, sampleRate: Double) -> BiquadCoefficients {
        let nyquistSafe = min(Double(band.frequency), sampleRate * 0.49)
        let a = pow(10, Double(band.gainDB) / 40)
        let w0 = 2 * Double.pi * nyquistSafe / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * max(Double(band.q), 0.01))
        let sqrtA2Alpha = 2 * sqrt(a) * alpha
        let (b0, b1, b2, a0, a1, a2): (Double, Double, Double, Double, Double, Double)
        switch band.type {
        case .peaking:
            (b0, b1, b2) = (1 + alpha * a, -2 * cosW, 1 - alpha * a)
            (a0, a1, a2) = (1 + alpha / a, -2 * cosW, 1 - alpha / a)
        case .lowShelf:
            b0 = a * ((a + 1) - (a - 1) * cosW + sqrtA2Alpha)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
            b2 = a * ((a + 1) - (a - 1) * cosW - sqrtA2Alpha)
            a0 = (a + 1) + (a - 1) * cosW + sqrtA2Alpha
            a1 = -2 * ((a - 1) + (a + 1) * cosW)
            a2 = (a + 1) + (a - 1) * cosW - sqrtA2Alpha
        case .highShelf:
            b0 = a * ((a + 1) + (a - 1) * cosW + sqrtA2Alpha)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
            b2 = a * ((a + 1) + (a - 1) * cosW - sqrtA2Alpha)
            a0 = (a + 1) - (a - 1) * cosW + sqrtA2Alpha
            a1 = 2 * ((a - 1) - (a + 1) * cosW)
            a2 = (a + 1) - (a - 1) * cosW - sqrtA2Alpha
        }
        return BiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Magnitude response in dB at `hz`.
    public func magnitudeDB(at hz: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * hz / sampleRate
        let (c1, s1, c2, s2) = (cos(w), sin(w), cos(2 * w), sin(2 * w))
        let numRe = b0 + b1 * c1 + b2 * c2, numIm = -(b1 * s1 + b2 * s2)
        let denRe = 1 + a1 * c1 + a2 * c2, denIm = -(a1 * s1 + a2 * s2)
        let mag2 = (numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm)
        return 10 * log10(mag2)
    }
}
