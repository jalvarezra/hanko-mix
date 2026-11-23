import Testing
@testable import PAVCore

@Test func balanceFullLeftSilencesRight() {
    var buf: [Float] = [0.3, 0.7, -0.2, 0.4, 0.9, -0.9]
    let original = buf
    buf.withUnsafeMutableBufferPointer { BalanceMono.apply($0.baseAddress!, frames: 3, balance: -1, mono: false) }
    for f in 0..<3 {
        #expect(buf[f * 2] == original[f * 2])
        #expect(buf[f * 2 + 1] == 0)
    }
}

@Test func monoAveragesChannels() {
    var buf: [Float] = [1, 0, 1, 0]
    buf.withUnsafeMutableBufferPointer { BalanceMono.apply($0.baseAddress!, frames: 2, balance: 0, mono: true) }
    #expect(buf == [0.5, 0.5, 0.5, 0.5])
}
