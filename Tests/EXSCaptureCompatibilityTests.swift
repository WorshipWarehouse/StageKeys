import Foundation

@main struct EXSCaptureCompatibilityTests {
    enum ProbeError: Error { case loadFailure }
    static func main() throws {
        let manager = FileManager.default
        let scratch = manager.temporaryDirectory.appendingPathComponent("StageKeys-EXS-test-" + UUID().uuidString)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("Selected")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let sampleName = "A modern capture sample with a long filename C4 v100.wav"
        let sample = root.appendingPathComponent(sampleName)
        let sampleBytes = Data("Sample bytes must be copied exactly".utf8)
        try sampleBytes.write(to: sample)
        func put32(_ value: UInt32, at index: Int, in data: inout Data) {
            for byte in 0..<4 { data[index + byte] = UInt8((value >> (byte * 8)) & 255) }
        }
        func putString(_ value: String, at index: Int, count: Int, in data: inout Data) {
            precondition(value.utf8.count < count)
            data.replaceSubrange(index..<index + count, with: Data(value.utf8) + Data(repeating: 0, count: count - value.utf8.count))
        }
        func chunk(_ signature: UInt32, size: Int) -> Data {
            var data = Data(repeating: 0x5A, count: 84 + size)
            put32(signature, at: 0, in: &data)
            put32(UInt32(size), at: 4, in: &data)
            data.replaceSubrange(16..<20, with: Data("TBOS".utf8))
            return data
        }
        func modern(_ name: String = "", directory: String = "/Old/Capture", signature: UInt32 = 0x43000101) -> Data {
            var data = chunk(signature, size: 1624)
            putString("Legacy truncated.wav", at: 20, count: 64, in: &data)
            putString("/Old/Legacy", at: 164, count: 256, in: &data)
            putString(name.isEmpty ? sampleName : name, at: 420, count: 256, in: &data)
            putString(directory, at: 684, count: 1024, in: &data)
            return data
        }
        func readString(_ data: Data, at index: Int, count: Int) -> String {
            String(data: data[index..<index + count].prefix(while: { $0 != 0 }), encoding: .utf8)!
        }
        let header = chunk(0x40000101, size: 0)
        let first = 84, second = 84 + 1708
        let original = header + modern() + modern(signature: 0x03000101)
        let preset = scratch.appendingPathComponent("Modern.exs")
        try original.write(to: preset)
        var temporary: URL?
        try EXSCaptureCompatibility.withCompatiblePreset(preset, sampleRoot: root) { compatible, temporaryRoot in
            temporary = temporaryRoot
            assert(compatible != preset && temporaryRoot != root)
            let normalized = try Data(contentsOf: compatible)
            assert(normalized.count == original.count)
            var mutable:[Range<Int>]=[]
            for position in [first,second] {
                mutable.append((position+20)..<(position+84))
                mutable.append((position+164)..<(position+676))
                mutable.append((position+684)..<(position+1708))
            }
            for index in original.indices where !mutable.contains(where: { $0.contains(index) }) {
                assert(normalized[index] == original[index], "Non-reference EXS byte changed at \(index)")
            }
            for position in [first, second] {
                assert(readString(normalized, at: position + 20, count: 64) == "s0.wav")
                assert(readString(normalized, at: position + 420, count: 256) == "s0.wav")
                assert(readString(normalized, at: position + 164, count: 256) == temporaryRoot.path)
                assert(readString(normalized, at: position + 684, count: 1024) == temporaryRoot.path)
            }
            let items = try manager.contentsOfDirectory(atPath: temporaryRoot.path)
            assert(Set(items) == Set(["s0.wav", "Instrument.exs"]), "Shared sample was copied more than once")
            let copied = try Data(contentsOf: temporaryRoot.appendingPathComponent("s0.wav"))
            assert(copied == sampleBytes)
        }
        assert(temporary != nil && !manager.fileExists(atPath: temporary!.path))
        let unchanged = try Data(contentsOf: preset)
        assert(unchanged == original, "Source EXS must never be rewritten")
        // The temporary copy must also disappear when the consumer throws.
        do {
            try EXSCaptureCompatibility.withCompatiblePreset(preset, sampleRoot: root) { _, staging in
                temporary = staging
                throw ProbeError.loadFailure
            }
            assertionFailure("Consumer failure was swallowed")
        } catch ProbeError.loadFailure {}
        assert(!manager.fileExists(atPath: temporary!.path))
        func temporaryNames() throws -> Set<String> {
            Set(try manager.contentsOfDirectory(atPath: manager.temporaryDirectory.path).filter {
                $0.hasPrefix("StageKeys-EXS-") && !$0.hasPrefix("StageKeys-EXS-test-")
            })
        }
        func rejects(_ bytes: Data, selectedRoot: URL = root) throws {
            let before = try temporaryNames()
            let malformed = scratch.appendingPathComponent(UUID().uuidString + ".exs")
            try bytes.write(to: malformed)
            var called = false
            do {
                try EXSCaptureCompatibility.withCompatiblePreset(malformed, sampleRoot: selectedRoot) { _, _ in called = true }
                assertionFailure("Invalid EXS input was accepted")
            } catch {}
            assert(!called, "Invalid references reached the native loader")
            let after = try temporaryNames()
            assert(after.subtracting(before).isEmpty, "Failed normalization leaked its staging directory")
        }
        // Existing samples outside the selected root cannot be copied.
        let outside = scratch.appendingPathComponent("Outside")
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        let secret = outside.appendingPathComponent("Outside.wav")
        try sampleBytes.write(to: secret)
        try rejects(header + modern("Outside.wav", directory: outside.path))
        // A symlink inside the selected root cannot bypass confinement.
        try manager.createSymbolicLink(at: root.appendingPathComponent("Escape.wav"), withDestinationURL: secret)
        try rejects(header + modern("Escape.wav", directory: root.path))
        // Size/truncation and invalid signature checks protect binary bounds.
        var oversized = original
        put32(UInt32.max, at: first + 4, in: &oversized)
        try rejects(oversized)
        try rejects(original.dropLast())
        var wrongMagic = original
        wrongMagic[first + 16] = 0
        try rejects(wrongMagic)
        var unterminatedName = original
        unterminatedName.replaceSubrange(first + 420..<first + 676, with: Data(repeating: 65, count: 256))
        try rejects(unterminatedName)
        var unterminatedDirectory = original
        unterminatedDirectory.replaceSubrange(first + 684..<first + 1708, with: Data(repeating: 65, count: 1024))
        try rejects(unterminatedDirectory)
        var emptyName = original
        emptyName[first + 420] = 0
        try rejects(emptyName)
        var invalidUTF8 = original
        invalidUTF8[first + 420] = 255
        try rejects(invalidUTF8)
        try rejects(header + modern("../Outside.wav", directory: root.path))
        // Unrecognized and legacy formats deliberately bypass normalization.
        let unknown = scratch.appendingPathComponent("Unknown.exs")
        try Data("Unrecognized format".utf8).write(to: unknown)
        try EXSCaptureCompatibility.withCompatiblePreset(unknown, sampleRoot: root) { url, directory in
            assert(url == unknown && directory == root)
        }
        let legacy = scratch.appendingPathComponent("Legacy.exs")
        try (header + chunk(0x03000101, size: 100)).write(to: legacy)
        try EXSCaptureCompatibility.withCompatiblePreset(legacy, sampleRoot: root) { url, directory in
            assert(url == legacy && directory == root)
        }
        print("PASS modern EXS reference-only edits, shared sample dedupe, source preservation, root/symlink confinement, malformed data rejection, passthrough, and cleanup")
    }
}
