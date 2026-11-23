/// Where the tap's audio sits among an aggregate's input streams. The output
/// subdevice's own input streams (e.g. a headset mic) come first and the tap's
/// stream comes last.
public enum TapStreamLayout {
    public static func tapStreamIndex(aggregateInputStreams: Int) -> Int? {
        aggregateInputStreams > 0 ? aggregateInputStreams - 1 : nil
    }

    /// Per-stream on/off flags for `kAudioDevicePropertyIOProcStreamUsage` (input
    /// scope): only the tap's stream is on, so a subdevice mic is never opened.
    public static func streamUsage(aggregateInputStreams: Int) -> [UInt32] {
        (0..<aggregateInputStreams).map { $0 == aggregateInputStreams - 1 ? 1 : 0 }
    }
}
