import CoreAudio
import Testing
@testable import PAVAudio

@Test func aggregateDescriptionHasPrivateDriftAndTap() {
    let d = AggregateDescription.make(uid: "io.github.jalvarezra.hankomix.agg.1", outputDeviceUID: "BuiltInSpeakerDevice", tapUID: "TAP-UUID")
    #expect(d[kAudioAggregateDeviceUIDKey] as? String == "io.github.jalvarezra.hankomix.agg.1")
    #expect(d[kAudioAggregateDeviceNameKey] as? String == "Hanko Mix")
    #expect(d[kAudioAggregateDeviceIsPrivateKey] as? Int == 1)
    #expect(d[kAudioAggregateDeviceMainSubDeviceKey] as? String == "BuiltInSpeakerDevice")
    #expect(d[kAudioAggregateDeviceTapAutoStartKey] as? Int == 1)
    let subdevices = d[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]]
    #expect(subdevices?.count == 1)
    #expect(subdevices?.first?[kAudioSubDeviceUIDKey] as? String == "BuiltInSpeakerDevice")
    #expect(subdevices?.first?[kAudioSubDeviceDriftCompensationKey] as? Int == 1)
    let taps = d[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
    #expect(taps?.count == 1)
    #expect(taps?.first?[kAudioSubTapUIDKey] as? String == "TAP-UUID")
    #expect(taps?.first?[kAudioSubTapDriftCompensationKey] as? Int == 1)
}
