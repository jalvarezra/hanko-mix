import Foundation

/// Readable names (and SF Symbols) for system audio processes whose raw name is a
/// daemon, bundle ID or executable path.
public enum FriendlyNames {
    private static let known: [String: (name: String, symbol: String)] = [
        "systemsoundserverd": ("System Sounds", "bell.fill"),
        "com.apple.PowerChime": ("Power Chime", "bolt.fill"),
        "com.apple.accessibility.heard": ("Background Sounds", "waveform"),
        "com.apple.Siri": ("Siri", "mic.fill"),
        "com.apple.CoreSpeech": ("Siri", "mic.fill"),
    ]

    public static func displayName(for id: AppID, fallback: String) -> String {
        if let entry = known[id.rawValue] { return entry.name }
        let name = fallback.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }
            .map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let isPath = id.rawValue.hasPrefix("/")
        let looksLikeIdentifier = !name.contains(" ") && name.contains(".")
        guard name == id.rawValue || isPath || looksLikeIdentifier else { return name.isEmpty ? id.rawValue : name }

        var base = isPath ? (id.rawValue as NSString).lastPathComponent : name
        if base.contains(".") { base = base.split(separator: ".").last.map(String.init) ?? base }
        return prettify(base)
    }

    public static func systemSymbol(for id: AppID) -> String? {
        known[id.rawValue]?.symbol
    }

    /// "SiriSetupSettingsIntents" → "Siri Setup Settings Intents"; "mediaanalysisd" → "Mediaanalysisd".
    private static func prettify(_ raw: String) -> String {
        var result = ""
        var previous: Character?
        for character in raw {
            if character.isUppercase, let p = previous, p.isLowercase { result.append(" ") }
            result.append(character)
            previous = character
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }
}
