import Testing
@testable import PAVAudio

@Test func averageOfChannelVolumes() {
    #expect(AudioDeviceControl.averageOfChannelVolumes([0.4, 0.6]) == 0.5)
    #expect(AudioDeviceControl.averageOfChannelVolumes([]) == nil)
}
