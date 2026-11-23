/// Linear gain ramp applied per frame to interleaved audio, so volume and mute
/// changes never produce clicks. Real-time safe: no allocation, no locks.
public struct GainRamp: Sendable {
    public private(set) var current: Float
    private var start: Float
    private var target: Float
    private var elapsedFrames = 0
    private var totalFrames = 0
    private let rampFrames: Int

    public init(sampleRate: Double, rampDuration: Double = 0.020, initial: Float = 1.0) {
        current = initial
        start = initial
        target = initial
        rampFrames = max(1, Int((rampDuration * sampleRate).rounded()))
    }

    public var isSettled: Bool { current == target }

    public mutating func setTarget(_ gain: Float) {
        start = current
        target = gain
        elapsedFrames = 0
        totalFrames = current == gain ? 0 : rampFrames
    }

    public mutating func apply(to buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        var index = 0
        for _ in 0..<frames {
            if elapsedFrames < totalFrames {
                elapsedFrames += 1
                // Interpolate from the start value instead of accumulating steps,
                // so rounding error never builds up.
                current = elapsedFrames == totalFrames
                    ? target
                    : start + (target - start) * (Float(elapsedFrames) / Float(totalFrames))
            }
            for _ in 0..<channels {
                buffer[index] *= current
                index += 1
            }
        }
    }
}
