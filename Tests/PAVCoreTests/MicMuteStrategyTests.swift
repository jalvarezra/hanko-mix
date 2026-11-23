import Testing
@testable import PAVCore

private func mic(volume: Float? = 0.7, volumeSettable: Bool = true, muted: Bool? = nil, muteSettable: Bool = false) -> InputDevice {
    InputDevice(uid: "mic", name: "Mic", transport: .builtIn, volume: volume, volumeSettable: volumeSettable, muted: muted, muteSettable: muteSettable)
}

@Test func deviceMuteIsUsedWhenAvailable() {
    let r = MicMuteStrategy.toggle(mic(muted: false, muteSettable: true), rememberedVolume: 0.3)
    #expect(r.action == .setMute(true))
    #expect(r.remember == 0.3)
}

@Test func deviceMuteUnmutes() {
    #expect(MicMuteStrategy.toggle(mic(muted: true, muteSettable: true), rememberedVolume: nil).action == .setMute(false))
}

@Test func volumeOnlyMuteRemembersVolume() {
    let r = MicMuteStrategy.toggle(mic(volume: 0.7), rememberedVolume: nil)
    #expect(r.action == .setVolume(0))
    #expect(r.remember == 0.7)
}

@Test func volumeOnlyUnmuteRestoresRememberedVolume() {
    let r = MicMuteStrategy.toggle(mic(volume: 0), rememberedVolume: 0.7)
    #expect(r.action == .setVolume(0.7))
    #expect(r.remember == nil)
}

@Test func volumeOnlyUnmuteWithoutMemoryRestoresHalf() {
    #expect(MicMuteStrategy.toggle(mic(volume: 0), rememberedVolume: nil).action == .setVolume(0.5))
}

@Test func unsupportedDeviceDoesNothing() {
    let d = mic(volume: nil, volumeSettable: false, muted: nil, muteSettable: false)
    #expect(MicMuteStrategy.toggle(d, rememberedVolume: nil).action == .unsupported)
    #expect(!MicMuteStrategy.isMuted(d))
}

@Test func volumeAtZeroCountsAsMutedOnlyWithoutDeviceMute() {
    #expect(MicMuteStrategy.isMuted(mic(volume: 0)))
    #expect(!MicMuteStrategy.isMuted(mic(volume: 0, muted: false, muteSettable: true)))
}
