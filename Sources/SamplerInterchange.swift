import Foundation

enum SamplerInterchangeError: LocalizedError {
    case unsupported, unsafePath, destinationExists, missingSample(String), invalidPreset
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Only imported Apple sampler presets can be exported as sampler bundles."
        case .unsafePath: return "The preset references a file outside its managed sound library."
        case .destinationExists: return "Choose a new folder; sampler export never overwrites an existing folder."
        case .missingSample(let name): return "A sampler sample is missing: \(name)."
        case .invalidPreset: return "The file is not a valid Apple sampler preset."
        }
    }
}

/// Portable sample-containing Apple sampler bundles. This is not a MainStage
/// patch/concert writer and does not imply third-party Sunday Keys app import.
enum SamplerInterchange {
    private static let samplerType: UInt32 = 0x61756D75 // aumu
    private static let samplerSubtype: UInt32 = 0x73616D70 // samp
    private static let appleManufacturer: UInt32 = 0x6170706C // appl
    private static func readPreset(_ url: URL) throws -> [String: Any] {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw SamplerInterchangeError.invalidPreset }
        let bytes = try Data(contentsOf: url)
        guard let state = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as? [String: Any],
              (state["type"] as? NSNumber)?.uint32Value == samplerType,
              (state["subtype"] as? NSNumber)?.uint32Value == samplerSubtype,
              (state["manufacturer"] as? NSNumber)?.uint32Value == appleManufacturer,
              state["Instrument"] is [String: Any],
              let references = state["file-references"] as? [String: String], references.count <= 4096 else {
            throw SamplerInterchangeError.invalidPreset
        }
        return state
    }
    private static func inside(_ file: URL, root: URL) -> Bool {
        file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/")
    }
    /// Export into a new folder. Returns the native .aupreset; every referenced
    /// sample is copied once. All unknown Instrument/zone data is preserved.
    static func exportPreset(_ sound: ExternalSound, libraryURL: URL, to folder: URL) throws -> URL {
        guard libraryURL.isFileURL, folder.isFileURL else { throw SamplerInterchangeError.unsafePath }
        guard sound.kind == .samplerPreset else { throw SamplerInterchangeError.unsupported }
        guard let name = sound.fileName, !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent else { throw SamplerInterchangeError.unsafePath }
        let manager = FileManager.default
        let source = libraryURL.appendingPathComponent(name)
        guard inside(source, root: libraryURL) else { throw SamplerInterchangeError.unsafePath }
        var state = try readPreset(source)
        let references = state["file-references"] as! [String: String]
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        guard !manager.fileExists(atPath: folder.path) else { throw SamplerInterchangeError.destinationExists }
        // createDirectory does not replace existing contents. The leaf is newly
        // created without creating arbitrary missing ancestor paths.
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".StageKeys-export-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let samples = staging.appendingPathComponent("Samples", isDirectory: true)
            try manager.createDirectory(at: samples, withIntermediateDirectories: false)
            var copied: [URL: String] = [:]
            var relocated: [String: String] = [:]
            for (key, path) in references.sorted(by: { $0.key < $1.key }) {
                let original: URL
                if path.hasPrefix("file://"), let parsed = URL(string: path), parsed.isFileURL { original = parsed }
                else if path.hasPrefix("/") { original = URL(fileURLWithPath: path) }
                else { original = source.deletingLastPathComponent().appendingPathComponent(path) }
                let resolved = original.resolvingSymlinksInPath().standardizedFileURL
                guard inside(resolved, root: libraryURL) else { throw SamplerInterchangeError.unsafePath }
                guard ["wav", "aif", "aiff", "caf", "flac"].contains(resolved.pathExtension.lowercased()),
                      (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    throw SamplerInterchangeError.missingSample(resolved.lastPathComponent)
                }
                let relative: String
                if let existing = copied[resolved] { relative = existing }
                else {
                    relative = "Samples/" + UUID().uuidString + "." + resolved.pathExtension.lowercased()
                    try manager.copyItem(at: resolved, to: staging.appendingPathComponent(relative))
                    copied[resolved] = relative
                }
                relocated[key] = folder.appendingPathComponent(relative).standardizedFileURL.path
            }
            state["file-references"] = relocated
            let preset = staging.appendingPathComponent("Instrument.aupreset")
            try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0).write(to: preset, options: .atomic)
            // Atomic publication refuses to replace an existing destination,
            // including one created after our initial existence check.
            try manager.moveItem(at: staging, to: folder)
            return folder.appendingPathComponent("Instrument.aupreset")
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }
    /// After moving a bundle, rebind its native preset to the included Samples.
    /// Only exact references within this bundle's Samples directory are accepted;
    /// no searches, external paths, or symlinks escaping the bundle are used.
    @discardableResult
    static func relinkPreset(at preset: URL) throws -> URL {
        guard preset.isFileURL else { throw SamplerInterchangeError.unsafePath }
        let root = preset.deletingLastPathComponent()
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        guard inside(preset, root: root) else { throw SamplerInterchangeError.unsafePath }
        var state = try readPreset(preset)
        let references = state["file-references"] as! [String: String]
        var relocated: [String: String] = [:]
        for (key, path) in references {
            let original = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let original, original.deletingLastPathComponent().lastPathComponent == "Samples",
                  !original.lastPathComponent.isEmpty else { throw SamplerInterchangeError.unsafePath }
            let sample = root.appendingPathComponent("Samples").appendingPathComponent(original.lastPathComponent)
            guard inside(sample, root: root), inside(sample, root: root.appendingPathComponent("Samples")) else { throw SamplerInterchangeError.unsafePath }
            guard ["wav", "aif", "aiff", "caf", "flac"].contains(sample.pathExtension.lowercased()),
                  (try? sample.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw SamplerInterchangeError.missingSample(sample.lastPathComponent)
            }
            relocated[key] = sample.standardizedFileURL.path
        }
        state["file-references"] = relocated
        try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0).write(to: preset, options: .atomic)
        return preset
    }

}
