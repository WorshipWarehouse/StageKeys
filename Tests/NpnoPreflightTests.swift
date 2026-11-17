import Foundation

@main struct NpnoPreflightTests {
    private static var checks = 0

    static func fixture(byteCount: Int = 120, container: String = "CBIN", type: String = "npno",
                        content: String = "CNSP") -> Data {
        var data = Data(repeating: 0x5A, count: byteCount)
        if byteCount >= 4 { data.replaceSubrange(0..<4, with: Data(container.utf8)) }
        if byteCount >= 8 { data.replaceSubrange(4..<8, with: Data([1, 0, 0, 0])) }
        if byteCount >= 12 { data.replaceSubrange(8..<12, with: Data(type.utf8)) }
        if byteCount >= 48 { data.replaceSubrange(44..<48, with: Data(content.utf8)) }
        return data
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        fatalError(message)
    }

    static func expect<T>(_ refusal: NpnoPreflight.Refusal, _ label: String, _ body: () throws -> T) {
        do {
            _ = try body()
            fail("FAIL: \(label) was accepted instead of refused as \(refusal.rawValue)")
        } catch let error as NpnoPreflight.Refusal {
            if error != refusal {
                fail("FAIL: \(label) refused as \(error.rawValue), expected \(refusal.rawValue)")
            }
        } catch {
            fail("FAIL: \(label) threw \(error)")
        }
        checks += 1
    }

    static func main() throws {
        let valid = fixture()
        let inspection = try NpnoPreflight.inspect(valid)
        assert(inspection.byteCount == valid.count)
        assert(inspection.state == .inspectionOnly,
               "An inspection must never publish a playable state")
        assert(NpnoPreflight.PlaybackState.allCases == [.inspectionOnly],
               "This increment has exactly one state: inspection-only")
        let kinds = inspection.spans.map { $0.kind }
        assert(kinds == [.container, .unclassified, .content, .unclassified],
               "Unexpected span classification: \(kinds)")
        assert(inspection.spans.map { $0.offset } == [0, 12, 44, 48],
               "Spans must stay in ascending order")
        assert(inspection.unclassifiedBytes == valid.count - 16,
               "Unclassified bytes must be the input minus the classified header and content tags")
        assert(inspection.sha256 == AssetDigest.sha256(valid),
               "The report must carry the hash of the unchanged input")

        var changed = valid
        changed[100] = 0x00
        let mutated = try NpnoPreflight.inspect(changed)
        assert(mutated.sha256 != inspection.sha256,
               "A changed input must produce a different hash")
        assert(mutated.spans == inspection.spans, "Only the digest changed, not the classification")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Astoria Grand XL.npno")
        try valid.write(to: file)
        let fromDisk = try NpnoPreflight.inspect(url: file)
        assert(fromDisk.sha256 == inspection.sha256 && fromDisk.byteCount == inspection.byteCount)
        assert(fromDisk.spans == inspection.spans && fromDisk.state == .inspectionOnly)

        expect(.empty, "an empty input") { try NpnoPreflight.inspect(Data()) }
        expect(.oversizedInput, "an input past the file ceiling") {
            try NpnoPreflight.inspect(valid, limits: .init(maximumFileBytes: 64))
        }
        expect(.truncated, "a 20-byte prefix") { try NpnoPreflight.inspect(fixture(byteCount: 20)) }
        expect(.unexpectedContainer, "a foreign container tag") {
            try NpnoPreflight.inspect(fixture(container: "CBAN"))
        }
        expect(.unexpectedType, "a non-piano type tag") {
            try NpnoPreflight.inspect(fixture(type: "nsmp"))
        }
        expect(.unsupportedLayout, "a content tag this build does not recognise") {
            try NpnoPreflight.inspect(fixture(content: "XXXX"))
        }
        expect(.unsupportedLayout, "a header read shorter than the observed content tag") {
            try NpnoPreflight.inspect(valid, limits: .init(maximumReadBytes: 40))
        }
        expect(.unclassifiedPayloadTooLarge, "payload beyond the inspection ceiling") {
            try NpnoPreflight.inspect(fixture(byteCount: 4096), limits: .init(maximumUnclassifiedBytes: 1024))
        }
        expect(.tooManySpans, "an unbounded span list") {
            try NpnoPreflight.validate(spans: (0..<9).map {
                NpnoPreflight.Span(kind: .unclassified, offset: $0 * 4, length: 4)
            }, fileLength: 64, limits: .init(maximumSpans: 8))
        }
        expect(.overlappingSpan, "overlapping spans") {
            try NpnoPreflight.validate(spans: [
                NpnoPreflight.Span(kind: .content, offset: 40, length: 8),
                NpnoPreflight.Span(kind: .unclassified, offset: 44, length: 8),
            ], fileLength: 64)
        }
        expect(.spanOutOfRange, "a span past the end of the input") {
            try NpnoPreflight.validate(spans: [
                NpnoPreflight.Span(kind: .content, offset: 60, length: 8),
            ], fileLength: 64)
        }
        expect(.spanOutOfRange, "an empty span") {
            try NpnoPreflight.validate(spans: [
                NpnoPreflight.Span(kind: .content, offset: 4, length: 0),
            ], fileLength: 64)
        }
        print("PASS: .npno preflight identifies the observed header, hashes the unchanged input, "
              + "publishes inspection-only state and refuses \(checks) limit/layout violations")
    }
}
