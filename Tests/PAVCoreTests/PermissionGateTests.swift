import Testing
@testable import PAVCore

@Test func deniedPermissionBlocksTapsAndShowsDeniedNotice() {
    let d = PermissionGate.decide(explained: true, status: .denied, wantsTaps: true)
    #expect(d.allowTaps == false)
    #expect(d.notice == .denied)
}

@Test func unexplainedUnknownPermissionAsksFirst() {
    let d = PermissionGate.decide(explained: false, status: .unknown, wantsTaps: true)
    #expect(d.allowTaps == false)
    #expect(d.notice == .explain)
}

@Test func explainedUnknownPermissionLetsMacOSPrompt() {
    #expect(PermissionGate.decide(explained: true, status: .unknown, wantsTaps: true) == .init(allowTaps: true, notice: nil))
}

@Test func alreadyAuthorizedSkipsExplanation() {
    #expect(PermissionGate.decide(explained: false, status: .authorized, wantsTaps: true) == .init(allowTaps: true, notice: nil))
}

@Test func noNoticeWhenNothingNeedsATap() {
    #expect(PermissionGate.decide(explained: false, status: .denied, wantsTaps: false).notice == nil)
}
