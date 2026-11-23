import Foundation

/// Soft-knee limiter: identity below `threshold`, smooth tanh compression above it,
/// guaranteeing |output| <= 1.0. Real-time safe.
public struct SoftLimiter: Sendable {
    public let threshold: Float

    /// Default threshold is -1 dBFS.
    public init(threshold: Float = 0.891) {
        self.threshold = threshold
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, count: Int) {
        let t = threshold
        let headroom = 1 - t
        for i in 0..<count {
            let x = buffer[i]
            let magnitude = abs(x)
            if magnitude > t {
                let limited = min(1, t + headroom * tanh((magnitude - t) / headroom))
                buffer[i] = x < 0 ? -limited : limited
            }
        }
    }
}
