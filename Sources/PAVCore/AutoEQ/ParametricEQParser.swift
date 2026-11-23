import Foundation

/// Parses AutoEQ `ParametricEQ.txt` files:
/// `Preamp: -6.2 dB` and `Filter N: ON PK|LSC|HSC Fc <hz> Hz Gain <db> dB Q <q>`.
public enum ParametricEQParser {
    public struct ParseError: Error, Equatable {
        public let message: String
    }

    public static func parse(_ text: String) throws -> (preampDB: Float, bands: [EQBand]) {
        var preamp: Float?
        var bands: [EQBand] = []
        var sawFilter = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let tokens = rawLine.split(separator: " ").map(String.init)
            guard let first = tokens.first else { continue }
            if first == "Preamp:", tokens.count >= 2, let value = Float(tokens[1]) {
                preamp = value
            } else if first == "Filter" {
                sawFilter = true
                guard tokens.count >= 12, tokens[2] == "ON" else { continue }
                let type: FilterType
                switch tokens[3] {
                case "PK": type = .peaking
                case "LSC", "LS": type = .lowShelf
                case "HSC", "HS": type = .highShelf
                default: continue
                }
                guard let fc = value(after: "Fc", in: tokens), let gain = value(after: "Gain", in: tokens),
                      let q = value(after: "Q", in: tokens) else {
                    throw ParseError(message: "Malformed filter line: \(rawLine)")
                }
                if bands.count < DeviceSettings.maxBands {
                    bands.append(EQBand(type: type, frequency: fc, gainDB: gain, q: q))
                }
            }
        }
        guard preamp != nil || sawFilter else { throw ParseError(message: "Not an AutoEQ ParametricEQ file") }
        return (preamp ?? 0, bands)
    }

    private static func value(after key: String, in tokens: [String]) -> Float? {
        guard let i = tokens.firstIndex(of: key), i + 1 < tokens.count else { return nil }
        return Float(tokens[i + 1])
    }
}
