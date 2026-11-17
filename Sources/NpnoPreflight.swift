import Foundation

/// Bounded, read-only inspection of a Nord piano (`.npno`) file.
///
/// This build recognises the header shape recorded for the owner's two 6.x piano
/// files and refuses everything else. It never decodes samples, never writes, and
/// publishes no playable state: `Inspection.state` is always `inspectionOnly`.
/// `Docs/NPNO-SUPPORT.md` records the contract, the evidence for each offset and
/// what is deliberately unsupported.
enum NpnoPreflight {
    /// Container signature observed at offset 0.
    static let containerTag = "CBIN"
    /// Piano type tag observed at offset 8.
    static let typeTag = "npno"
    /// Content-section tag observed at offset 44.
    static let contentTag = "CNSP"
    static let tagBytes = 4
    /// Offsets of the observed tags. They are observations of the two private
    /// examples, not documented fields of the format.
    static let containerTagOffset = 0
    static let typeTagOffset = 8
    static let contentTagOffset = 44
    /// Smallest input this build recognises: through the observed content tag.
    static let minimumBytes = contentTagOffset + tagBytes

    /// Explicit work limits. Every input is held to these before any payload is
    /// read, hashed or copied.
    struct Limits: Equatable {
        /// Largest file this build will inspect at all.
        var maximumFileBytes = 64 << 20
        /// Largest run of bytes the classifier may leave unclassified.
        var maximumUnclassifiedBytes = 48 << 20
        /// Bytes read from disk to identify the container, type and content tags.
        var maximumReadBytes = 64
        /// Spans an inspection report may carry.
        var maximumSpans = 8

        static let standard = Limits()
    }

    /// Every refusal names the violated limit or format assumption.
    enum Refusal: String, Error, Equatable {
        case empty
        case oversizedInput
        case truncated
        case unexpectedContainer
        case unexpectedType
        case unsupportedLayout
        case unclassifiedPayloadTooLarge
        case tooManySpans
        case overlappingSpan
        case spanOutOfRange
        case inputChanged
    }

    /// A classified byte range. Spans describe bytes only; nothing is decoded.
    struct Span: Equatable {
        enum Kind: String {
            case container
            case type
            case content
            case unclassified
        }
        var kind: Kind
        var offset: Int
        var length: Int
    }

    /// Inspection only. This build has no decoded or playable state to publish.
    enum PlaybackState: String, CaseIterable {
        case inspectionOnly = "inspection-only"
    }

    struct Inspection: Equatable {
        var byteCount: Int
        var sha256: String
        var spans: [Span]
        var unclassifiedBytes: Int
        var state: PlaybackState
    }

    /// Inspects in-memory bytes. Refusals are raised before the input is hashed.
    static func inspect(_ data: Data, limits: Limits = .standard) throws -> Inspection {
        let spans = try classify(prefix: data.prefix(limits.maximumReadBytes),
                                 byteCount: data.count, limits: limits)
        return report(spans: spans, byteCount: data.count, digest: AssetDigest.sha256(data))
    }

    /// Inspects a file without loading it: only `maximumReadBytes` are read to
    /// classify it, and the digest streams the same opened file.
    static func inspect(url: URL, limits: Limits = .standard) throws -> Inspection {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: min(max(size, 0), limits.maximumReadBytes)) ?? Data()
        let spans = try classify(prefix: prefix, byteCount: size, limits: limits)
        let digest = try digest(handle: handle, expectedBytes: size, limits: limits)
        try verify(prefix: prefix, handle: handle)
        return report(spans: spans, byteCount: size, digest: digest)
    }

    /// Hashes the same opened file from its start, refusing output that does not
    /// match the length the classification was made from. A file replaced or
    /// rewritten between classification and hashing is refused, not reported.
    static func digest(handle: FileHandle, expectedBytes: Int, limits: Limits = .standard) throws -> String {
        guard expectedBytes > 0 else { throw Refusal.empty }
        guard expectedBytes <= limits.maximumFileBytes else { throw Refusal.oversizedInput }
        _ = try handle.seek(toOffset: 0)
        let streamed = try AssetDigest.sha256(handle, byteCount: expectedBytes)
        guard streamed.read == expectedBytes else { throw Refusal.inputChanged }
        guard (try handle.read(upToCount: 1))?.isEmpty != false else { throw Refusal.inputChanged }
        return streamed.digest
    }

    /// Re-reads the classified prefix from the same opened file and compares it
    /// byte for byte, so content rewritten in place between classification and
    /// hashing is refused instead of being reported with the earlier header.
    /// Bytes past the prefix make no content claim: they are described by length
    /// only, and the digest covers whatever was read for them.
    static func verify(prefix: Data, handle: FileHandle) throws {
        guard !prefix.isEmpty else { return }
        _ = try handle.seek(toOffset: 0)
        let again = try handle.read(upToCount: prefix.count) ?? Data()
        guard again == prefix else { throw Refusal.inputChanged }
    }

    /// Classifies the observed header and fills the gaps as unclassified bytes.
    /// The four-byte word at offset 4 stays unclassified because its meaning is
    /// unknown, not because it is believed to be a version.
    static func classify(prefix: Data, byteCount: Int, limits: Limits = .standard) throws -> [Span] {
        guard byteCount > 0 else { throw Refusal.empty }
        guard byteCount <= limits.maximumFileBytes else { throw Refusal.oversizedInput }
        guard byteCount >= minimumBytes else { throw Refusal.truncated }
        guard prefix.count >= minimumBytes else { throw Refusal.unsupportedLayout }
        guard tag(prefix, at: containerTagOffset) == containerTag else { throw Refusal.unexpectedContainer }
        guard tag(prefix, at: typeTagOffset) == typeTag else { throw Refusal.unexpectedType }
        guard tag(prefix, at: contentTagOffset) == contentTag else { throw Refusal.unsupportedLayout }
        var spans: [Span] = []
        var cursor = 0
        for (kind, offset) in [(Span.Kind.container, containerTagOffset),
                               (Span.Kind.type, typeTagOffset),
                               (Span.Kind.content, contentTagOffset)] {
            if offset > cursor { spans.append(Span(kind: .unclassified, offset: cursor, length: offset - cursor)) }
            spans.append(Span(kind: kind, offset: offset, length: tagBytes))
            cursor = offset + tagBytes
        }
        if byteCount > cursor { spans.append(Span(kind: .unclassified, offset: cursor, length: byteCount - cursor)) }
        try validate(spans: spans, fileLength: byteCount, limits: limits)
        let unclassified = spans.filter { $0.kind == .unclassified }.reduce(0) { $0 + $1.length }
        guard unclassified <= limits.maximumUnclassifiedBytes else { throw Refusal.unclassifiedPayloadTooLarge }
        return spans
    }

    /// Refuses spans that leave the input, overlap, or exceed the output limit.
    static func validate(spans: [Span], fileLength: Int, limits: Limits = .standard) throws {
        guard spans.count <= limits.maximumSpans else { throw Refusal.tooManySpans }
        var cursor = 0
        for span in spans.sorted(by: { $0.offset < $1.offset }) {
            guard span.length > 0 else { throw Refusal.spanOutOfRange }
            guard span.length <= fileLength, span.offset >= 0, span.offset <= fileLength - span.length else {
                throw Refusal.spanOutOfRange
            }
            guard span.offset >= cursor else { throw Refusal.overlappingSpan }
            cursor = span.offset + span.length
        }
    }

    /// Assembles the report. Every limit is already enforced by `classify`, so a
    /// refused input is never hashed and this step cannot fail after hashing.
    static func report(spans: [Span], byteCount: Int, digest: String) -> Inspection {
        let unclassified = spans.filter { $0.kind == .unclassified }.reduce(0) { $0 + $1.length }
        return Inspection(byteCount: byteCount, sha256: digest, spans: spans,
                          unclassifiedBytes: unclassified, state: .inspectionOnly)
    }

    private static func tag(_ bytes: Data, at offset: Int) -> String? {
        guard offset >= 0 else { return nil }
        let slice = bytes.dropFirst(offset).prefix(tagBytes)
        guard slice.count == tagBytes, slice.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(decoding: slice, as: UTF8.self)
    }
}
