import Foundation
import Testing
@testable import PAVCore

private let fixture = """
Preamp: -6.2 dB
Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 2: ON PK Fc 180 Hz Gain -3.1 dB Q 0.53
Filter 3: ON PK Fc 1200 Hz Gain 2.4 dB Q 1.10
Filter 4: ON PK Fc 2300 Hz Gain -4.0 dB Q 2.00
Filter 5: ON PK Fc 3100 Hz Gain 3.3 dB Q 3.50
Filter 6: ON PK Fc 5200 Hz Gain -2.2 dB Q 4.10
Filter 7: ON PK Fc 6800 Hz Gain 1.0 dB Q 2.60
Filter 8: ON PK Fc 8100 Hz Gain -1.5 dB Q 5.00
Filter 9: ON PK Fc 9400 Hz Gain 0.8 dB Q 3.00
Filter 10: ON HSC Fc 10000 Hz Gain -2.0 dB Q 0.70
"""

@Test func parsesPreampAndFilters() throws {
    let result = try ParametricEQParser.parse(fixture)
    #expect(result.preampDB == -6.2)
    #expect(result.bands.count == 10)
    #expect(result.bands[0] == EQBand(type: .lowShelf, frequency: 105, gainDB: 5.5, q: 0.70))
    #expect(result.bands[1] == EQBand(type: .peaking, frequency: 180, gainDB: -3.1, q: 0.53))
    #expect(result.bands[9] == EQBand(type: .highShelf, frequency: 10_000, gainDB: -2.0, q: 0.70))
}

@Test func ignoresOffFilters() throws {
    let text = "Preamp: -1 dB\nFilter 1: OFF PK Fc 100 Hz Gain 1 dB Q 1\nFilter 2: ON PK Fc 200 Hz Gain 2 dB Q 1\n"
    let result = try ParametricEQParser.parse(text)
    #expect(result.bands == [EQBand(type: .peaking, frequency: 200, gainDB: 2, q: 1)])
}

@Test func rejectsGarbage() {
    #expect(throws: (any Error).self) { try ParametricEQParser.parse("hello world") }
}

private let catalog = AutoEQCatalog(entries: [
    AutoEQEntry(name: "Sennheiser HD 650", source: "oratory1990", form: "over-ear", preampDB: -6, bands: []),
    AutoEQEntry(name: "Sony WH-1000XM4", source: "oratory1990", form: "over-ear", preampDB: -5, bands: []),
    AutoEQEntry(name: "Moondrop Blessing 2", source: "crinacle", form: "in-ear", preampDB: -4, bands: []),
    AutoEQEntry(name: "HD 650 Clone Mod", source: "crinacle", form: "over-ear", preampDB: -3, bands: []),
])

@Test func searchFindsHeadphoneCaseInsensitive() {
    #expect(catalog.search("hd 650").map(\.name).contains("Sennheiser HD 650"))
    #expect(catalog.search("SONY wh").map(\.name) == ["Sony WH-1000XM4"])
    #expect(catalog.search("mööndrop").map(\.name) == ["Moondrop Blessing 2"])
}

@Test func searchPrefersPrefixMatch() {
    #expect(catalog.search("hd 650").first?.name == "HD 650 Clone Mod")
}

@Test func catalogRoundTripsThroughJSON() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("autoeq-\(UUID()).json")
    try JSONEncoder().encode(catalog.entries).write(to: url)
    #expect(try AutoEQCatalog.loadBundled(from: url).entries == catalog.entries)
}

@Test func locatesCatalogInsideAppStyleResourceBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pav-locate-\(UUID())")
    let nested = root.appendingPathComponent("X.bundle/Contents/Resources")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: nested.appendingPathComponent("autoeq.json"))
    #expect(AutoEQCatalog.locate(bundleName: "X.bundle", searchRoots: [root])?.lastPathComponent == "autoeq.json")
}

@Test func locatesCatalogInFlatResourceBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pav-locate-\(UUID())")
    let flat = root.appendingPathComponent("X.bundle")
    try FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: flat.appendingPathComponent("autoeq.json"))
    #expect(AutoEQCatalog.locate(bundleName: "X.bundle", searchRoots: [URL(fileURLWithPath: "/nonexistent"), root]) != nil)
}
