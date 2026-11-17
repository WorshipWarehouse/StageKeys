import Foundation

/// Planning rules for adding several user-selected sound files as one library
/// transaction (#8). Deliberately free of AVFoundation and Core Audio, so
/// selection order, source identity, duplicate detection and the user-facing
/// summary are verifiable without a Mac, an Xcode build or an installed
/// instrument.
enum LibraryBulkImport {
    /// Extensions that are prepared from the selected file alone. EXS and
    /// AUPRESET instruments still ask for the folder that holds their samples,
    /// so a multi-file selection stays limited to self-contained sources.
    static let selfContainedExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "sf2", "dls"]

    static func needsSampleFolder(_ url: URL) -> Bool {
        !selfContainedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Deterministic selection order with repeated paths removed. A picker can
    /// return the same file twice; each distinct file is prepared once.
    static func uniqueSources(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls.map({ $0.standardizedFileURL }).sorted(by: { $0.path < $1.path }) {
            if seen.insert(url.path).inserted { result.append(url) }
        }
        return result
    }

    /// Name of the installed sound whose content digest matches this source.
    /// Managed copies and retained originals both keep the digest of the file
    /// the user selected, so importing it again never adds a second copy.
    static func duplicateName(digest: String, in entries: [LibrarySound]) -> String? {
        guard digest.count == 64 else { return nil }
        return entries.first { $0.managedFileSHA256 == digest || $0.originalInstrument?.sha256 == digest }?.name
    }

    /// A bounded, user-facing name for a selected file.
    static func displayName(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((name.isEmpty ? url.lastPathComponent : name).prefix(80))
    }

    /// Per-file result of one batch. Counts, not an open-ended log, drive the
    /// summary the import view shows.
    enum Outcome: Equatable {
        case added(name: String)
        case skipped(name: String, reason: String)
        case failed(name: String, reason: String)
    }

    static func addedNames(_ outcomes: [Outcome]) -> [String] {
        outcomes.compactMap { (outcome: Outcome) -> String? in
            if case .added(let name) = outcome { return name }
            return nil
        }
    }

    static func skippedNames(_ outcomes: [Outcome]) -> [String] {
        outcomes.compactMap { (outcome: Outcome) -> String? in
            if case .skipped(let name, _) = outcome { return name }
            return nil
        }
    }

    static func failures(_ outcomes: [Outcome]) -> [(name: String, reason: String)] {
        outcomes.compactMap { (outcome: Outcome) -> (name: String, reason: String)? in
            if case .failed(let name, let reason) = outcome { return (name, reason) }
            return nil
        }
    }

    /// The committed result in the order the user reads it: what was added,
    /// what was already present, then why the rest was rejected. The first
    /// three failures are named so a mixed selection stays actionable.
    static func summary(_ outcomes: [Outcome]) -> String {
        let added = addedNames(outcomes)
        let skipped = skippedNames(outcomes)
        let failed = failures(outcomes)
        var parts: [String] = []
        if added.count == 1, let name = added.first {
            parts.append("Added \(name) to My Sounds.")
        } else if !added.isEmpty {
            parts.append("Added \(added.count) sounds to My Sounds.")
        }
        if !skipped.isEmpty {
            parts.append("Skipped \(skipped.count) already installed or selected twice.")
        }
        if !failed.isEmpty {
            let detail = failed.prefix(3).map { "\($0.name) (\($0.reason))" }.joined(separator: "; ")
            parts.append("\(failed.count) failed: \(detail)\(failed.count > 3 ? "; …" : "")")
        }
        return parts.isEmpty ? "No sounds were added." : parts.joined(separator: " ")
    }

    /// A failure message is shown beside its file, never as an unbounded blob.
    static func failureReason(_ error: Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Unknown error" : String(text.prefix(200))
    }
}
