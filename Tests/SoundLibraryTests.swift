import Foundation
@main struct SoundLibraryTests {
    static func tryRead(_ library:SoundLibrary) -> [LibrarySound] { try! library.read() }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SoundLibrary(url: root.appendingPathComponent("library.json"))
        let empty = try library.read(); assert(empty.isEmpty)
        let native = LibrarySound(id: "sample", name: "Sample", collection: "My Sounds", sound: ExternalSound(kind: .sample, name: "Sample", fileName: "sample.wav"))
        let host = LibrarySound(id: "host", name: "Free Pad", collection: "Sunday Free · Volume 1", hostPath: "/private/example.patch")
        let complete = LibrarySound(id:"layer",name:"Layer",collection:"My Sounds",layer:Layer(name:"Layer",instrument:1,gain:0.5))
        try library.write([native, host, complete]); let loaded = try library.read(); assert(loaded == [native, host, complete])
        var imported = native
        imported.id = "ableton-samples-existing-id"
        imported.name = "Free Piano · Ableton Samples"
        imported.sound!.name = imported.name
        imported.collection = "Sunday Free Ableton · Volume 1"
        try library.write([imported])
        let cleaned = try library.read()[0]
        assert(cleaned.id == imported.id && cleaned.name == "Free Piano")
        assert(cleaned.sound?.name == "Free Piano" && cleaned.sound?.fileName == imported.sound?.fileName)
        assert(cleaned.collection == "Sunday Free · Volume 1")
        assert(SoundLibrary.cleanImportedName("My Ableton Piano") == "My Ableton Piano")
        try library.write(loaded)
        var bad = complete; bad.layer!.gain = .nan
        do { try library.write([bad]); assertionFailure("Invalid sound accepted") } catch {}
        assert(tryRead(library) == loaded)
        try Data("invalid".utf8).write(to: library.url)
        do { _ = try library.read(); assertionFailure("Malformed library accepted") } catch {}
        let preserved = try String(contentsOf: library.url, encoding: .utf8); assert(preserved == "invalid")
        let files = root.appendingPathComponent("samples")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Data().write(to: files.appendingPathComponent("instrument.aupreset"))
        try Data().write(to: files.appendingPathComponent("instrument.exs"))
        try Data().write(to: files.appendingPathComponent("audio.wav"))
        try FileManager.default.createSymbolicLink(at: files.appendingPathComponent("escape.aupreset"), withDestinationURL: library.url)
        let discovered = try SoundLibrary.samplerPresets(in: files)
        assert(Set(discovered.map(\.lastPathComponent)) == ["instrument.aupreset", "instrument.exs"])
        print("PASS: native and host sound library round-trip; corrupt library preserved")
    }
}
