/// Stereo balance and mono downmix on interleaved stereo audio. Real-time safe.
public enum BalanceMono {
    /// - Parameters:
    ///   - balance: -1 (full left) … 0 (center) … 1 (full right).
    public static func apply(_ buffer: UnsafeMutablePointer<Float>, frames: Int, balance: Float, mono: Bool) {
        let leftGain: Float = balance > 0 ? 1 - balance : 1
        let rightGain: Float = balance < 0 ? 1 + balance : 1
        for f in 0..<frames {
            var l = buffer[f * 2], r = buffer[f * 2 + 1]
            if mono {
                let m = (l + r) * 0.5
                l = m; r = m
            }
            buffer[f * 2] = l * leftGain
            buffer[f * 2 + 1] = r * rightGain
        }
    }
}
