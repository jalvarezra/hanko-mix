import Testing
@testable import PAVCore

@Test func balanceSnapsToCenterNearZero() {
    #expect(Snap.balance(0.04) == 0)
    #expect(Snap.balance(-0.04) == 0)
    #expect(Snap.balance(0.2) == 0.2)
}

@Test func volumeSnapsToUnityNear100Percent() {
    #expect(Snap.volume(0.98) == 1)
    #expect(Snap.volume(1.02) == 1)
    #expect(Snap.volume(0.9) == 0.9)
}
