import Foundation

/// Selection, identity and summary rules for multi-file library import (#8).
/// Pure planning logic: no audio device, plug-in or fixture is opened.
struct LongImportFailure: LocalizedError {
    var errorDescription: String? { String(repeating: "y", count: 400) }
}

@main struct LibraryBulkImportTests {
    static func main() throws {
        let base = URL(fileURLWithPath: "/tmp/stagekeys-bulk")
        let alpha = base.appendingPathComponent("Alpha.wav")
        let beta = base.appendingPathComponent("Beta.aif")

        // A repeated selection is prepared once, in a deterministic order that
        // does not follow the picker's own ordering.
        assert(LibraryBulkImport.uniqueSources([beta, alpha, beta]).map(\.lastPathComponent) == ["Alpha.wav", "Beta.aif"])
        assert(LibraryBulkImport.uniqueSources([alpha, base.appendingPathComponent("sub/../Alpha.wav")]).count == 1)
        assert(LibraryBulkImport.uniqueSources([]).isEmpty)

        // Only sampler instruments need the extra folder prompt, so the picker
        // refuses to import several of those in one batch.
        assert(LibraryBulkImport.needsSampleFolder(base.appendingPathComponent("Piano.EXS")))
        assert(LibraryBulkImport.needsSampleFolder(base.appendingPathComponent("Kit.aupreset")))
        assert(LibraryBulkImport.needsSampleFolder(base.appendingPathComponent("Odd.xyz")))
        assert(!LibraryBulkImport.needsSampleFolder(base.appendingPathComponent("Pad.wav")))
        assert(!LibraryBulkImport.needsSampleFolder(base.appendingPathComponent("Bank.SF2")))
        assert(!LibraryBulkImport.needsSampleFolder(base.appendingPathComponent("Take.AIFF")))

        // Content identity covers both a managed copy and a retained original.
        let managedDigest = String(repeating: "a", count: 64)
        let retainedDigest = String(repeating: "b", count: 64)
        var managed = LibrarySound(id: "managed", name: "Managed Pad", collection: "My Sounds",
                                   layer: Layer(name: "Pad", instrument: 1, gain: 0.5))
        managed.managedFileSHA256 = managedDigest
        var retained = LibrarySound(id: "retained", name: "Retained Piano", collection: "My Sounds",
                                    layer: Layer(name: "Piano", instrument: 2, gain: 0.5))
        retained.originalInstrument = StageKeysSampler.Original(
            file: "Original Instruments/" + retainedDigest + ".exs", sha256: retainedDigest)
        let existing = [managed, retained]
        assert(LibraryBulkImport.duplicateName(digest: managedDigest, in: existing) == "Managed Pad")
        assert(LibraryBulkImport.duplicateName(digest: retainedDigest, in: existing) == "Retained Piano")
        assert(LibraryBulkImport.duplicateName(digest: String(repeating: "c", count: 64), in: existing) == nil)
        // A digest that is not a SHA-256 hex string can never claim a match.
        assert(LibraryBulkImport.duplicateName(digest: "abc", in: existing) == nil)

        // The summary counts a mixed batch and names the first failures only.
        let mixed: [LibraryBulkImport.Outcome] = [
            .added(name: "Felt Piano"),
            .added(name: "Strings"),
            .skipped(name: "Felt Piano", reason: "Already in My Sounds"),
            .failed(name: "Broken.exs", reason: "The instrument could not be read.")
        ]
        let summary = LibraryBulkImport.summary(mixed)
        assert(summary == "Added 2 sounds to My Sounds. Skipped 1 already installed or selected twice. 1 failed: Broken.exs (The instrument could not be read.)", summary)
        assert(LibraryBulkImport.summary([.added(name: "Felt Piano")]) == "Added Felt Piano to My Sounds.")
        assert(LibraryBulkImport.summary([.skipped(name: "Pad.wav", reason: "Repeated selection")]) == "Skipped 1 already installed or selected twice.")
        assert(LibraryBulkImport.summary([]) == "No sounds were added.")
        let manyFailures = (0..<5).map { LibraryBulkImport.Outcome.failed(name: "File \($0)", reason: "Rejected") }
        let many = LibraryBulkImport.summary(manyFailures)
        assert(many == "5 failed: File 0 (Rejected); File 1 (Rejected); File 2 (Rejected); …", many)

        // Failure text shown beside a file stays bounded.
        assert(LibraryBulkImport.failureReason(LongImportFailure()).count == 200)
        assert(LibraryBulkImport.failureReason(CocoaError(.fileReadNoSuchFile)) == CocoaError(.fileReadNoSuchFile).localizedDescription)
        assert(LibraryBulkImport.displayName(base.appendingPathComponent(String(repeating: "n", count: 120) + ".wav")).count == 80)

        print("PASS: bulk import selection order, sampler-instrument boundary, duplicate identity, bounded summary and failure text")
    }
}
