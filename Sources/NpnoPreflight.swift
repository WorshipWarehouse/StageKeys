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
    /// Offset of `contentTag`, recorded as an observation of the two private
    /// examples rather than a documented field of the format.
    static let contentTagOffset = 44
    /// Classified prefix: `CBIN`, an unidentified four-byte word, then `npno`.
    static let headerBytes = 12
    /// Smallest input this build recognises: through the observed content tag.
    static let minimumBytes = contentTagOffset + 4

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
        let spans = try classify(prefix: data.prefix(limits.maximumReadBytes), byteCount: data.count, limits: limits)
        return try report(spans: spans, byteCount: data.count, digest: AssetDigest.sha256(data), limits: limits)
    }

    /// Inspects a file without loading it: only `maximumReadBytes` are read to
    /// classify it, and the digest streams the unchanged bytes.
    static func inspect(url: URL, limits: Limits = .standard) throws -> Inspection {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw Refusal.empty }
        guard size <= limits.maximumFileBytes else { throw Refusal.oversizedInput }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: min(size, limits.maximumReadBytes)) ?? Data()
        let spans = try classify(prefix: prefix, byteCount: size, limits: limits)
        return try report(spans: spans, byteCount: size, digest: AssetDigest.sha256(url), limits: limits)
    }

    /// Classifies the observed header and fills the gaps as unclassified bytes.
    /// The four-byte word at offset 4 is reported as unclassified because its
    /// meaning is unknown, not because it is believed to be a version.
    static func classify(prefix: Data, byteCount: Int, limits: Limits = .standard) throws -> [Span] {
        guard byteCount > 0 else { throw Refusal.empty }
        guard byteCount <= limits.maximumFileBytes else { throw Refusal.oversizedInput }
        guard byteCount >= minimumBytes else { throw Refusal.truncated }
        guard tag(prefix, at: 0) == containerTag else { throw Refusal.unexpectedContainer }
        guard tag(prefix, at: 8) == typeTag else { throw Refusal.unexpectedType }
        guard tag(prefix, at: contentTagOffset) == contentTag else { throw Refusal.unsupportedLayout }
        var spans: [Span] = []
        var cursor = 0
        for (kind, offset, length) in [(Span.Kind.container, 0, headerBytes),
                                       (Span.Kind.content, contentTagOffset, 4)] {
            if offset > cursor { spans.append(Span(kind: .unclassified, offset: cursor, length: offset - cursor)) }
            spans.append(Span(kind: kind, offset: offset, length: length))
            cursor = offset + length
        }
        if byteCount > cursor { spans.append(Span(kind: .unclassified, offset: cursor, length: byteCount - cursor)) }
        try validate(spans: spans, fileLength: byteCount, limits: limits)
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

    /// Builds the report, refusing before publication when the unclassified
    /// payload exceeds the inspection ceiling.
    static func report(spans: [Span], byteCount: Int, digest: String,
                       limits: Limits = .standard) throws -> Inspection {
        let unclassified = spans.filter { $0.kind == .unclassified }.reduce(0) { $0 + $1.length }
        guard unclassified <= limits.maximumUnclassifiedBytes else { throw Refusal.unclassifiedPayloadTooLarge }
        return Inspection(byteCount: byteCount, sha256: digest, spans: spans,
                          unclassifiedBytes: unclassified, state: .inspectionOnly)
    }

    private static func tag(_ bytes: Data, at offset: Int) -> String? {
        guard offset >= 0 else { return nil }
        let slice = bytes.dropFirst(offset).prefix(4)
        guard slice.count == 4, slice.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(decoding: slice, as: UTF8.self)
    }
}
