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

    enum Problem: Error, Equatable, CustomStringConvertible, LocalizedError {
        var errorDescription: String? { description }
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

    /// The raw-buffer entrypoint owns the same admission limits as the `Data`
    /// one, so a caller cannot bypass the bounded contract by wrapping bytes.
    static func inspect(_ bytes: UnsafeRawBufferPointer, limits: Limits) throws -> Report {
        if bytes.count == 0 { throw Problem.empty }
        if bytes.count > limits.maximumFileBytes { throw Problem.fileTooLarge(bytes: bytes.count, maximum: limits.maximumFileBytes) }
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

        let rawName = try text(bytes, at: headerBytes + 0x1c, length: 32, bodyStart: headerBytes)
        guard !rawName.isEmpty else { throw Problem.invalidText(offset: 0x1c) }
        let parts = rawName.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var variant: String?
        if parts.count == 2, !parts[1].isEmpty { variant = String(parts[1]) }
        _ = try text(bytes, at: headerBytes + 0x3c, length: 32, bodyStart: headerBytes)
        var voicing: String?
        if streamVersion == 0x464 {
            let value = try text(bytes, at: headerBytes + 0x5c, length: 32, bodyStart: headerBytes)
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
        let blocks = (origin + audioAlignmentBias + blockBytes - 1) / blockBytes
        return blocks * blockBytes - audioAlignmentBias
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
    /// Bytes after the terminator are padding, so they must be an empty byte or
    /// a space: anything else means this is not the padded text the container
    /// documents, and the field is reported instead of partially read.
    private static func text(_ bytes: UnsafeRawBufferPointer, at offset: Int, length: Int, bodyStart: Int) throws -> String {
        let reported = offset - bodyStart
        var slice: [UInt8] = []
        var index = offset
        while index < offset + length {
            let byte = bytes[index]
            if byte == 0 {
                var padding = index + 1
                while padding < offset + length {
                    guard bytes[padding] == 0 || bytes[padding] == 0x20 else { throw Problem.invalidText(offset: reported) }
                    padding += 1
                }
                break
            }
            guard byte >= 0x20, byte != 0x7f else { throw Problem.invalidText(offset: reported) }
            slice.append(byte)
            index += 1
        }
        guard let value = String(bytes: slice, encoding: .utf8) else { throw Problem.invalidText(offset: reported) }
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

// Stroke layout and codec adapted from John Moore's BSD-3-Clause nord-format,
// drawbar tree 210472d0b462a663a731b44966f478f50ce8a091.
// See Licenses/Drawbar-BSD-3-Clause.txt. This does not establish Nord sonic parity.
extension NordPiano {
    struct DecodeFailure: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    struct Stroke: Equatable {
        let root, bank, layer, threshold: Int
        let frames, blocks, offset: Int
        let seeds: [[Int64]]
        let loopStart, loopEnd, trim, noteOffFade: Int
    }
    struct Index {
        let report: Report
        let strokes: [Stroke]
        let keyMap: [Int]
        let fineTune: [Int]
        let decodedBytes: Int
    }
    static let sampleRate = 35_002
    /// PCM admission is independent of compressed size. Decode one stroke at a time.
    static let maximumDecodedBytes = 1_500_000_000
    static let maximumStrokeFrames = sampleRate * 180
    static func index(_ data: Data) throws -> Index {
        let report = try inspect(data)
        guard report.generation == 1, case .verified = report.checksum else {
            throw DecodeFailure(reason: "Playback requires a type-1 container with a verified CRC32.")
        }
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = 0x2c
            func u16(_ at: Int) -> Int { Int(be16(raw, at: base + at)) }
            func u32(_ at: Int) -> Int { Int(be32(raw, at: base + at)) }
            var strokes: [Stroke] = [], cursor = report.audioStart, total = 0
            for root in 0..<128 {
                for _ in 0..<u16(0x622 + root * 2) {
                    let record = prefixBytes + strokes.count * strokeRecordBytes
                    let offset = u32(record), frames = u32(record + 6), blocks = u16(record + 10)
                    let size = blocks * report.audioBlockBytes
                    guard offset == cursor, blocks > 0, frames > 0,
                          frames <= maximumStrokeFrames,
                          frames <= blocks * ((report.audioBlockBytes - 2) * 8 / report.channels - 64),
                          size <= data.count - base - cursor else {
                        throw DecodeFailure(reason: "Invalid or excessive stroke span at record \(strokes.count).")
                    }
                    total += frames * report.channels * 2
                    guard total <= maximumDecodedBytes else { throw DecodeFailure(reason: "Decoded piano exceeds the 1.5 GB limit.") }
                    let seeds = (0..<2).map { channel in (0..<4).map { i in
                        Int64(Int16(bitPattern: UInt16(u16(record + 12 + (channel * 4 + i) * 2))))
                    } }
                    strokes.append(Stroke(root: root, bank: Int(raw[base + record + 4]), layer: Int(raw[base + record + 5]),
                        threshold: Int(raw[base + record + 0x74]), frames: frames, blocks: blocks, offset: base + offset, seeds: seeds,
                        loopStart: u32(record + 0x1c), loopEnd: u32(record + 0x1c) + u32(record + 0x20),
                        trim: Int(Int16(bitPattern: UInt16(u16(record + 0x34)))), noteOffFade: Int(raw[base + record + 0x72])))
                    cursor += size
                }
            }
            guard cursor == data.count - base else { throw DecodeFailure(reason: "Unclaimed bytes follow the last stroke.") }
            let roots = Set(strokes.map(\.root))
            let keys = (0..<128).map { Int(raw[base + 0x8c + $0]) }
            guard keys.allSatisfy({ $0 == 255 || roots.contains($0) }) else { throw DecodeFailure(reason: "Key map references an absent root.") }
            return Index(report: report, strokes: strokes, keyMap: keys,
                fineTune: (0..<128).map { Int(Int8(bitPattern: raw[base + 0x18c + $0])) }, decodedBytes: total)
        }
    }

    /// Lossless integer PCM; refuses malformed predictors, clipping, overlaps and
    /// frame counts. Cancellation is checked every block, outside the render thread.
    static func decode(_ data: Data, stroke: Stroke, channels: Int,
                       cancelled: () -> Bool = { false }) throws -> [Int16] {
        guard (1...2).contains(channels) else { throw DecodeFailure(reason: "Invalid channel count.") }
        let blockBytes = 1022 * channels
        guard stroke.blocks > 0, stroke.frames > 0,
              stroke.frames <= maximumStrokeFrames, stroke.seeds.count == 2,
              stroke.seeds.allSatisfy({ $0.count == 4 }), stroke.offset >= 0,
              stroke.offset <= data.count, stroke.blocks <= (data.count - stroke.offset) / blockBytes else {
            throw DecodeFailure(reason: "Invalid decode request.")
        }
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let coefficients: [[Int64]] = [[], [1], [2, -1], [3, -3, 1], [4, -6, 4, -1]]
            var history = stroke.seeds.map { Array($0.reversed()) }
            var tail: [Int16] = [], result: [Int16] = []
            result.reserveCapacity(stroke.frames * channels)
            for block in 0..<stroke.blocks {
                if cancelled() { throw CancellationError() }
                let at = stroke.offset + block * blockBytes
                let header = Int(be16(raw, at: at)), width = header & 31, order = (header >> 5) & 7
                guard (1...16).contains(width), order <= 4 else { throw DecodeFailure(reason: "Unsupported residual width or predictor order.") }
                let frames = (blockBytes - 2) * 8 / (width * channels), owned = frames - 64
                guard owned >= 4, owned <= stroke.frames - result.count / channels else { throw DecodeFailure(reason: "Block exceeds declared frame count.") }
                var reservoir: UInt64 = 0, held = 0, next = at + 2
                var decoded: [Int16] = []; decoded.reserveCapacity(frames * channels)
                for _ in 0..<frames {
                    for channel in 0..<channels {
                        while held < width {
                            guard next + 2 <= at + blockBytes else { throw DecodeFailure(reason: "Truncated residual fields.") }
                            reservoir |= UInt64(be16(raw, at: next)) << held
                            held += 16; next += 2
                        }
                        let bits = Int64(reservoir & ((1 << width) - 1)), sign: Int64 = 1 << (width - 1)
                        reservoir >>= width; held -= width
                        var value = (bits ^ sign) - sign
                        for j in 0..<order {
                            let product = history[channel][j].multipliedReportingOverflow(by: coefficients[order][j])
                            let sum = value.addingReportingOverflow(product.partialValue)
                            guard !product.overflow, !sum.overflow else { throw DecodeFailure(reason: "Predictor overflow.") }
                            value = sum.partialValue
                        }
                        guard let sample = Int16(exactly: value) else { throw DecodeFailure(reason: "Decoded sample clips; codec does not describe this stroke.") }
                        decoded.append(sample)
                        history[channel][3] = history[channel][2]
                        history[channel][2] = history[channel][1]
                        history[channel][1] = history[channel][0]
                        history[channel][0] = value
                    }
                }
                if !tail.isEmpty, !decoded.prefix(tail.count).elementsEqual(tail) { throw DecodeFailure(reason: "Block overlap mismatch.") }
                for channel in 0..<channels {
                    history[channel] = (0..<4).map { Int64(decoded[(owned - 1 - $0) * channels + channel]) }
                }
                result.append(contentsOf: decoded.prefix(owned * channels))
                tail = Array(decoded.suffix(64 * channels))
            }
            guard result.count == stroke.frames * channels else { throw DecodeFailure(reason: "Decoded frame count differs from the record.") }
            return result
        }
    }
}

extension NordPiano {
    struct Zone: Equatable {
        let stroke, key, velocityLow, velocityHigh: Int
        let fineTuneCents, gainDB: Double
    }
    /// Electro 5 Touch 0 measurements from nord-format; interpolated switching
    /// estimate, not a verified curve for every Nord instrument.
    static func topVelocity(_ threshold: Int) -> Int {
        let reach = [127,107,105,99,93,85,79,73,67,61,57,53,51,45,43,39,33,31,27,23,21]
        guard (0...200).contains(threshold) else { return 0 }
        let step = threshold / 10, into = threshold % 10
        return reach[step] - ((reach[step] - reach[min(step + 1, 20)]) * into + 9) / 10
    }
    /// Explicit attack-only translation. All other banks remain unmodified in
    /// the input and are listed as unsupported, never mixed into attack layers.
    static func zones(_ index: Index, libraryGain: Int) throws -> [Zone] {
        var result: [Zone] = []
        var selections: [Int:[Int]] = [:]
        let attacks = Dictionary(grouping:index.strokes.indices.filter { index.strokes[$0].bank == 0 }, by:{index.strokes[$0].root})
        for (root,candidates) in attacks {
            let layers=Set(candidates.map{index.strokes[$0].layer}).sorted()
            var louder: [Int:Int] = [:]
            for (position,layer) in layers.enumerated() {louder[layer] = position == 0 ? 0:layers[position-1]}
            let thresholds=candidates.map { i -> (Int,Int) in
                let stroke=index.strokes[i]
                return (i,index.report.streamVersion == 0x464 ? stroke.threshold:((louder[stroke.layer,default:0]+stroke.layer)*5+1)/2)
            }
            var selected: [Int] = []
            for velocity in 1...127 {
                var best: Int?, bestThreshold = -1
                for (i,threshold) in thresholds where velocity <= topVelocity(threshold) && threshold >= bestThreshold {
                    best=i;bestThreshold=threshold
                }
                guard let best else {throw DecodeFailure(reason:"Velocity map leaves a gap at root \(root), velocity \(velocity).")}
                selected.append(best)
            }
            selections[root]=selected
        }
        for key in 0..<128 where index.keyMap[key] != 255 {
            guard let selected=selections[index.keyMap[key]] else {throw DecodeFailure(reason:"A covered key has no attack recording.")}
            var low = 1
            while low <= 127 {
                let i = selected[low - 1], stroke = index.strokes[i]
                var high = low
                while high < 127, selected[high] == i { high += 1 }
                guard stroke.loopStart >= 0, stroke.loopEnd >= stroke.loopStart, stroke.loopEnd <= stroke.frames else {
                    throw DecodeFailure(reason: "Unsupported loop marks at stroke \(i).")
                }
                if index.report.streamVersion == 0x450, stroke.trim < 0 { throw DecodeFailure(reason: "Negative version-5 trim needs silent-zone translation.") }
                let gain = index.report.streamVersion == 0x464 ? Double(min(108, libraryGain - stroke.trim)) / 10 : Double(libraryGain) / 10 - Double(stroke.trim)
                guard (-96...24).contains(gain) else { throw DecodeFailure(reason: "Stroke gain exceeds native limits.") }
                result.append(Zone(stroke:i,key:key,velocityLow:low,velocityHigh:high,fineTuneCents:Double(index.fineTune[key])*0.7,gainDB:gain))
                low = high + 1
            }
        }
        guard !result.isEmpty, result.count <= 16384 else { throw DecodeFailure(reason: "Empty or excessive native zone map.") }
        return result
    }
    static func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= Limits().maximumFileBytes else {
            throw DecodeFailure(reason: "Choose a regular .npno file no larger than 512 MiB.")
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: size + 1) ?? Data()
        guard bytes.count == size else { throw DecodeFailure(reason: "Source changed or was truncated while reading.") }
        return bytes
    }
}
