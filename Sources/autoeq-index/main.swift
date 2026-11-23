import Foundation
import PAVCore

// Builds the bundled AutoEQ index from a checkout of jaakkopasanen/AutoEq.
// Usage: autoeq-index <path/AutoEq/results> <output.json>

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: autoeq-index <path/AutoEq/results> <output.json>\n".utf8))
    exit(64)
}
let resultsURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: arguments[2])
let sourcePriority = ["oratory1990", "crinacle", "rtings", "innerfidelity"]

func rank(_ source: String) -> Int { sourcePriority.firstIndex(of: source) ?? sourcePriority.count }

var best: [String: AutoEQEntry] = [:]
var skipped = 0
let enumerator = FileManager.default.enumerator(at: resultsURL, includingPropertiesForKeys: nil)!
for case let url as URL in enumerator where url.lastPathComponent.hasSuffix("ParametricEQ.txt") {
    // results/<source>/[…]/<form>/<name>/<name> ParametricEQ.txt
    let components = url.standardizedFileURL.pathComponents.dropFirst(resultsURL.pathComponents.count)
    guard components.count >= 4 else { skipped += 1; continue }
    let parts = Array(components)
    let source = parts[0]
    let name = parts[parts.count - 2]
    let rig = parts[parts.count - 3].lowercased()   // e.g. "GRAS 43AG-7 over-ear"
    let form = ["in-ear", "over-ear", "earbud"].first { rig.contains($0) } ?? rig
    guard let text = try? String(contentsOf: url, encoding: .utf8),
          let parsed = try? ParametricEQParser.parse(text) else { skipped += 1; continue }
    let entry = AutoEQEntry(name: name, source: source, form: form, preampDB: parsed.preampDB, bands: parsed.bands)
    if let existing = best[name], rank(existing.source) <= rank(source) { continue }
    best[name] = entry
}

let entries = best.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(entries).write(to: outputURL, options: .atomic)
print("Wrote \(entries.count) presets to \(outputURL.path) (skipped \(skipped) files)")
