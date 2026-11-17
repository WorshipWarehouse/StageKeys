import Foundation

/// Bounded, read-only inspection of a Nord piano library (`.npno`).
///
/// This is a preflight only. It reports the container and metadata prefix it can
/// verify and refuses structurally invalid input; it decodes no audio, copies no
/// body bytes and never labels a file playable. Accepted versions, field
/// provenance, limits and the open licensing/content questions are recorded in
/// `Docs/NORD-NPNO-SCOPE.md`.
enum NordPiano {
    /// Support-contract revision reported with every inspection result.
    static let contractVersion = 1
    /// Stream versions whose prefix offsets are documented and validated.
    static let supportedStreamVersions: Set<UInt16> = [0x450, 0x464]
    static let prefixBytes = 0x732
    static let strokeRecordBytes = 118
    /// Frames one encoded block covers; a span is a whole number of blocks.
    static let blockFrames = 1022
    /// The audio grid's offset from a whole number of blocks (unexplained).
    static let audioAlignmentBias = 192

    struct Limits {
        var maximumFileBytes = 512 << 20
        var maximumStrokes = 4096
    }

    /// The container's checksum verdict. `unestablished` means the algorithm or
    /// its byte order is not documented well enough to compare for this
    /// generation, not that the file passed.
    enum Checksum: Equatable {
        case verified(UInt32)
        case mismatch(stored: UInt32, computed: UInt32)
        case unestablished
    }

    struct Report: Equatable {
        var generation: Int
        var contentVersion: UInt32
        var streamVersion: UInt16
        var name: String
        var variant: String?
        var voicing: String?
        var channels: Int
        var strokes: Int
        var coveredKeys: Int
        var directoryEnd: Int
        var audioStart: Int
        var audioBytes: Int
        var audioBlockBytes: Int
        var checksum: Checksum
        /// Observed facts that are not rejections but must not be read as a
        /// playable or verified-file claim.
        var notes: [String]
    }

    enum Problem: Error, Equatable, CustomStringConvertible {
        case empty
        case fileTooLarge(bytes: Int, maximum: Int)
        case truncatedHeader(bytes: Int, minimum: Int)
        case badMagic
        case unsupportedGeneration(UInt32)
        case wrongFormatTag(String)
        case badStreamMagic
        case bodyTooSmall(bytes: Int, minimum: Int)
        case unsupportedStreamVersion(UInt16)
        case streamVersionEchoMismatch(echo: UInt16, stream: UInt16)
        case invalidChannelCount(UInt16)
        case invalidStrokeCount(Int)
        case strokeCountMismatch(table: Int, declared: Int)
        case directoryOverflow(end: Int, bodyBytes: Int)
        case audioGridOutsideBody(start: Int, bodyBytes: Int)
        case nonZeroAlignmentGap(offset: Int)
        case missingAudio
        case audioNotBlockAligned(bytes: Int, block: Int)
        case invalidText(offset: Int)

        var description: String {
            switch self {
            case .empty: return "The file is empty."
            case .fileTooLarge(let bytes, let maximum): return "The file is \(bytes) bytes; this reader accepts at most \(maximum)."
            case .truncatedHeader(let bytes, let minimum): return "The file is \(bytes) bytes and does not hold the \(minimum)-byte container header."
            case .badMagic: return "The file does not begin with the CBIN container magic."
            case .unsupportedGeneration(let word): return "The container generation word \(word) is neither 0 nor 1."
            case .wrongFormatTag(let tag): return "The container tag is \"\(tag)\", not the piano-library tag."
            case .badStreamMagic: return "The body does not begin with the CNSP stream magic."
            case .bodyTooSmall(let bytes, let minimum): return "The body is \(bytes) bytes and does not hold the \(minimum)-byte metadata prefix."
            case .unsupportedStreamVersion(let version): return "The stream version 0x\(String(version, radix: 16)) is not one this reader validates."
            case .streamVersionEchoMismatch(let echo, let stream): return "The stream version is echoed as 0x\(String(echo, radix: 16)), not 0x\(String(stream, radix: 16))."
            case .invalidChannelCount(let channels): return "The channel count \(channels) is neither 1 nor 2."
            case .invalidStrokeCount(let strokes): return "The stroke count \(strokes) is zero or above the configured limit."
            case .strokeCountMismatch(let table, let declared): return "The per-root count table sums to \(table), not the declared \(declared) strokes."
            case .directoryOverflow(let end, let bodyBytes): return "The stroke directory ends at \(end) but the body is \(bodyBytes) bytes."
            case .audioGridOutsideBody(let start, let bodyBytes): return "The aligned audio start \(start) is outside the \(bodyBytes)-byte body."
            case .nonZeroAlignmentGap(let offset): return "The alignment gap before the audio is not zero at body offset \(offset)."
            case .missingAudio: return "The body holds no encoded audio after the stroke directory."
            case .audioNotBlockAligned(let bytes, let block): return "The audio region is \(bytes) bytes, not a whole number of \(block)-byte blocks."
            case .invalidText(let offset): return "The text field at body offset \(offset) holds bytes that are not printable text."
            }
        }
    }

    static func inspect(_ data: Data, limits: Limits = Limits()) throws -> Report {
        if data.isEmpty { throw Problem.empty }
        if data.count > limits.maximumFileBytes { throw Problem.fileTooLarge(bytes: data.count, maximum: limits.maximumFileBytes) }
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Report in
            try inspect(raw, limits: limits)
        }
    }

    static func inspect(_ bytes: UnsafeRawBufferPointer, limits: Limits) throws -> Report {
        guard bytes.count >= 0x2c else { throw Problem.truncatedHeader(bytes: bytes.count, minimum: 0x2c) }
        guard ascii(bytes, at: 0, length: 4) == "CBIN" else { throw Problem.badMagic }
        let generationWord = le32(bytes, at: 4)
        guard generationWord == 0 || generationWord == 1 else { throw Problem.unsupportedGeneration(generationWord) }
        let tag = ascii(bytes, at: 8, length: 4) ?? ""
        guard tag == "npno" else { throw Problem.wrongFormatTag(tag) }
        let contentVersion = le32(bytes, at: 0x14)
        let headerBytes = generationWord == 1 ? 0x2c : 0x18
        guard bytes.count > headerBytes + 2 else { throw Problem.truncatedHeader(bytes: bytes.count, minimum: headerBytes + 3) }
        let bodyEnd = generationWord == 1 ? bytes.count : bytes.count - 2
        let bodyBytes = bodyEnd - headerBytes

        // The prefix offsets below are relative to the body's first byte, so the
        // whole prefix is validated before any field is read.
        guard bodyBytes >= prefixBytes else { throw Problem.bodyTooSmall(bytes: bodyBytes, minimum: prefixBytes) }
        guard ascii(bytes, at: headerBytes, length: 4) == "CNSP" else { throw Problem.badStreamMagic }
        let streamVersion = be16(bytes, at: headerBytes + 0x04)
        guard supportedStreamVersions.contains(streamVersion) else { throw Problem.unsupportedStreamVersion(streamVersion) }
        let echo = be16(bytes, at: headerBytes + 0x61c)
        guard echo == streamVersion else { throw Problem.streamVersionEchoMismatch(echo: echo, stream: streamVersion) }
        let channels = be16(bytes, at: headerBytes + 0x61e)
        guard channels == 1 || channels == 2 else { throw Problem.invalidChannelCount(channels) }
        let strokes = Int(be16(bytes, at: headerBytes + 0x620))
        guard strokes > 0, strokes <= limits.maximumStrokes else { throw Problem.invalidStrokeCount(strokes) }
        var declared = 0
        var root = 0
        while root < 128 {
            declared += Int(be16(bytes, at: headerBytes + 0x622 + root * 2))
            root += 1
        }
        guard declared == strokes else { throw Problem.strokeCountMismatch(table: declared, declared: strokes) }

        let directoryEnd = prefixBytes + strokes * strokeRecordBytes
        guard directoryEnd <= bodyBytes else { throw Problem.directoryOverflow(end: directoryEnd, bodyBytes: bodyBytes) }
        let blockBytes = blockFrames * Int(channels)
        let audioStart = alignedAudioStart(after: directoryEnd, blockBytes: blockBytes)
        guard audioStart >= directoryEnd, audioStart <= bodyBytes else {
            throw Problem.audioGridOutsideBody(start: audioStart, bodyBytes: bodyBytes)
        }
        var offset = directoryEnd
        while offset < audioStart {
            if bytes[headerBytes + offset] != 0 { throw Problem.nonZeroAlignmentGap(offset: offset) }
            offset += 1
        }
        let audioBytes = bodyBytes - audioStart
        guard audioBytes > 0 else { throw Problem.missingAudio }
        guard audioBytes % blockBytes == 0 else { throw Problem.audioNotBlockAligned(bytes: audioBytes, block: blockBytes) }

        let rawName = try text(bytes, at: headerBytes + 0x1c, length: 32)
        guard !rawName.isEmpty else { throw Problem.invalidText(offset: 0x1c) }
        let parts = rawName.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var variant: String?
        if parts.count == 2, !parts[1].isEmpty { variant = String(parts[1]) }
        _ = try text(bytes, at: headerBytes + 0x3c, length: 32)
        var voicing: String?
        if streamVersion == 0x464 {
            let value = try text(bytes, at: headerBytes + 0x5c, length: 32)
            if !value.isEmpty { voicing = value }
        }
        var coveredKeys = 0
        var key = 0
        while key < 128 {
            if bytes[headerBytes + 0x8c + key] != 0xFF { coveredKeys += 1 }
            key += 1
        }

        var notes = [
            "Inspection only: no sample decoding, mapping or playback is claimed, and the file is not labelled playable.",
            "Per-stroke audio spans are not validated yet: only the region's alignment and total size are checked.",
            "The header's location and aux words are not interpreted; in a piano library they do not hold a bank and slot.",
        ]
        var checksum: Checksum = .unestablished
        if generationWord == 1 {
            let storedLE = le32(bytes, at: 0x18)
            let computed = crc32(bytes, from: headerBytes, to: bodyEnd)
            if computed == storedLE || computed == be32(bytes, at: 0x18) {
                checksum = .verified(computed)
            } else {
                checksum = .mismatch(stored: storedLE, computed: computed)
                notes.append("The container checksum \(storedLE) does not match the computed \(computed); review the file before using it.")
            }
            var reserved = 0x1c
            while reserved < 0x2c {
                if bytes[reserved] != 0 { notes.append("A reserved container header byte at 0x\(String(reserved, radix: 16)) is not zero.") ; break }
                reserved += 1
            }
        } else {
            notes.append("Type-0 container checksum is not verified: the covering bytes and polynomial are only inferred, so it cannot reject a file.")
        }

        return Report(generation: generationWord == 1 ? 1 : 0,
                      contentVersion: contentVersion,
                      streamVersion: streamVersion,
                      name: String(parts[0]),
                      variant: variant,
                      voicing: voicing,
                      channels: Int(channels),
                      strokes: strokes,
                      coveredKeys: coveredKeys,
                      directoryEnd: directoryEnd,
                      audioStart: audioStart,
                      audioBytes: audioBytes,
                      audioBlockBytes: blockBytes,
                      checksum: checksum,
                      notes: notes)
    }

    /// The first position at or after `origin` on the documented audio grid:
    /// whole blocks offset by the alignment bias.
    static func alignedAudioStart(after origin: Int, blockBytes: Int) -> Int {
        let base = max(origin, audioAlignmentBias)
        let blocks = (base - audioAlignmentBias + blockBytes - 1) / blockBytes
        return audioAlignmentBias + blocks * blockBytes
    }

    // MARK: - Byte helpers

    private static func be16(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func be32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func le32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func ascii(_ bytes: UnsafeRawBufferPointer, at offset: Int, length: Int) -> String? {
        var slice: [UInt8] = []
        var index = offset
        while index < offset + length {
            slice.append(bytes[index])
            index += 1
        }
        return String(bytes: slice, encoding: .utf8)
    }

    /// Reads a NUL-padded field, rejecting control bytes rather than guessing.
    private static func text(_ bytes: UnsafeRawBufferPointer, at offset: Int, length: Int) throws -> String {
        var slice: [UInt8] = []
        var index = offset
        while index < offset + length {
            let byte = bytes[index]
            if byte == 0 { break }
            guard byte >= 0x20, byte != 0x7f else { throw Problem.invalidText(offset: offset) }
            slice.append(byte)
            index += 1
        }
        guard let value = String(bytes: slice, encoding: .utf8) else { throw Problem.invalidText(offset: offset) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private static func crc32(_ bytes: UnsafeRawBufferPointer, from start: Int, to end: Int) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        var index = start
        while index < end {
            crc = crcTable[Int((crc ^ UInt32(bytes[index])) & 0xff)] ^ (crc >> 8)
            index += 1
        }
        return crc ^ 0xFFFF_FFFF
    }
}
