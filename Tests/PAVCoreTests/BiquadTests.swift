import Testing
@testable import PAVCore

@Test func peakingBandHasGainAtCenter() {
    let c = BiquadCoefficients.make(EQBand(type: .peaking, frequency: 1000, gainDB: 6, q: 1), sampleRate: 48_000)
    #expect(abs(c.magnitudeDB(at: 1000, sampleRate: 48_000) - 6) < 0.05)
    #expect(abs(c.magnitudeDB(at: 50, sampleRate: 48_000)) < 0.5)
}

@Test func lowShelfAndHighShelfReachGainAtExtremes() {
    let low = BiquadCoefficients.make(EQBand(type: .lowShelf, frequency: 105, gainDB: -3, q: 0.7), sampleRate: 48_000)
    #expect(abs(low.magnitudeDB(at: 20, sampleRate: 48_000) - (-3)) < 0.3)
    let high = BiquadCoefficients.make(EQBand(type: .highShelf, frequency: 10_000, gainDB: 4, q: 0.7), sampleRate: 48_000)
    #expect(abs(high.magnitudeDB(at: 20_000, sampleRate: 48_000) - 4) < 0.3)
}

@Test func coefficientsChangeWithSampleRate() {
    let band = EQBand(type: .peaking, frequency: 1000, gainDB: 6, q: 1)
    #expect(BiquadCoefficients.make(band, sampleRate: 44_100) != BiquadCoefficients.make(band, sampleRate: 48_000))
}
