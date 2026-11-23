import Foundation

public struct AutoEQEntry: Codable, Sendable, Hashable {
    public var name: String
    public var source: String
    public var form: String
    public var preampDB: Float
    public var bands: [EQBand]

    public init(name: String, source: String, form: String, preampDB: Float, bands: [EQBand]) {
        self.name = name
        self.source = source
        self.form = form
        self.preampDB = preampDB
        self.bands = bands
    }
}


/// Searchable list of AutoEQ headphone presets.
public struct AutoEQCatalog: Sendable {
    public let entries: [AutoEQEntry]
    private let normalizedNames: [String]

    public init(entries: [AutoEQEntry]) {
        self.entries = entries
        normalizedNames = entries.map { Self.normalize($0.name) }
    }

    public static func loadBundled(from url: URL) throws -> AutoEQCatalog {
        AutoEQCatalog(entries: try JSONDecoder().decode([AutoEQEntry].self, from: Data(contentsOf: url)))
    }

    /// Finds `autoeq.json` inside a SwiftPM resource bundle under any of `searchRoots`,
    /// supporting both the flat layout (`swift run`) and the `Contents/Resources`
    /// layout (copied into an `.app`).
    public static func locate(bundleName: String, searchRoots: [URL]) -> URL? {
        for root in searchRoots {
            let bundleURL = root.appendingPathComponent(bundleName)
            if let url = Bundle(url: bundleURL)?.url(forResource: "autoeq", withExtension: "json") { return url }
            for candidate in [bundleURL.appendingPathComponent("Contents/Resources/autoeq.json"),
                              bundleURL.appendingPathComponent("autoeq.json")]
            where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Case- and accent-insensitive token search; names starting with the query rank first.
    public func search(_ query: String, limit: Int = 20) -> [AutoEQEntry] {
        let q = Self.normalize(query)
        let tokens = q.split(separator: " ")
        guard !tokens.isEmpty else { return [] }
        let matches = entries.indices.filter { i in tokens.allSatisfy { normalizedNames[i].contains($0) } }
        let ranked = matches.sorted { a, b in
            let pa = normalizedNames[a].hasPrefix(q), pb = normalizedNames[b].hasPrefix(q)
            if pa != pb { return pa }
            return normalizedNames[a].count < normalizedNames[b].count
        }
        return ranked.prefix(limit).map { entries[$0] }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
