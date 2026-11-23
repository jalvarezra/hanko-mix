import Testing
@testable import PAVAudio

@Test func tapIsTheLastInputStreamWhenTheDeviceHasAMic() {
    // A USB headset contributes one mic input stream before the tap's stream.
    #expect(TapStreamLayout.tapStreamIndex(aggregateInputStreams: 2) == 1)
    #expect(TapStreamLayout.streamUsage(aggregateInputStreams: 2) == [0, 1])
}

@Test func tapIsTheOnlyInputStreamOnOutputOnlyDevices() {
    #expect(TapStreamLayout.tapStreamIndex(aggregateInputStreams: 1) == 0)
    #expect(TapStreamLayout.streamUsage(aggregateInputStreams: 1) == [1])
}

@Test func noInputStreamsMeansNoTapStream() {
    #expect(TapStreamLayout.tapStreamIndex(aggregateInputStreams: 0) == nil)
}
