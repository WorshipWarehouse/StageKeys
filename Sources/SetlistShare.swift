import Foundation
import CryptoKit
import UniformTypeIdentifiers

extension UTType {
    /// StageKeys-owned portable setlist document. The package carries the setlist
    /// graph and references only; sample and plug-in payloads never travel here.
    static var stageKeysSetlistShare: UTType {
        UTType(exportedAs: "studio.stagekeys.setlist-share", conformingTo: .json)
    }
}

enum SetlistShareError: LocalizedError {
    case invalidFormat, unsupportedVersion, tooLarge, linkTooLarge, checksum, unsafeContent, invalidContent
    case activationBlocked(String)
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "This file is not a StageKeys setlist share package."
        case .unsupportedVersion: return "This setlist share was made by an unsupported StageKeys version."
        case .tooLarge: return "This setlist share exceeds the 8 MB package limit."
        case .linkTooLarge: return "This setlist is too large for an offline link. Share it as a .stagekeyssetlist file instead."
        case .checksum: return "This setlist share is damaged or was changed after it was exported."
        case .unsafeContent: return "This setlist share contains content StageKeys does not accept from a shared file."
        case .invalidContent: return "This setlist share contains an invalid setlist."
        case .activationBlocked(let reason): return reason
        }
    }
}

/// A self-contained, versioned setlist document. `content` includes the setlist
/// graph, metadata and dependency references; it never includes sample bytes,
/// plug-in binaries or plug-in state. `checksum` is SHA-256 over the canonical
/// JSON of `content`, so an accidentally edited package is refused. It is an
/// integrity check, not a signature; schema and payload validation still run on
/// every import even when a package was deliberately resealed.
struct SetlistSharePackage: Codable {
    struct Dependency: Codable, Hashable, Identifiable {
        enum Kind: String, Codable {
            case audioUnit, samplerPreset, tonicPad, sample, soundBank, externalMIDI
        }
        var kind: Kind
        var name: String
        var identifier: String
        var detail: String
        var id: String { kind.rawValue + "|" + identifier }
        var kindTitle: String {
            switch kind {
            case .audioUnit: return "Audio Unit"
            case .samplerPreset: return "Sampler instrument"
            case .tonicPad: return "Tonic Pad instrument"
            case .sample: return "Sample"
            case .soundBank: return "Sound bank"
            case .externalMIDI: return "External MIDI"
            }
        }
    }
    struct Content: Codable {
        var setlist: Setlist
        var dependencies: [Dependency]
        var warnings: [String]
    }
    static let formatIdentifier = "stagekeys-setlist-share"
    static let supportedVersion = 1
    static let byteLimit = 8_000_000
    var format: String
    var version: Int
    var exportedAt: Date
    var checksum: String
    var content: Content

    init(format: String, version: Int, exportedAt: Date, checksum: String, content: Content) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.checksum = checksum
        self.content = content
    }

    init(source: Setlist) throws {
        try SetlistShare.validateForExport(source)
        let omittedPluginState = SetlistShare.containsPluginState(source)
        var portable = source
        SetlistShare.sanitize(&portable)
        try portable.validate()
        let dependencies = SetlistShare.dependencies(in: portable)
        guard dependencies.count <= SetlistShare.maximumDependencies else { throw SetlistShareError.invalidContent }
        let warnings = SetlistShare.warnings(in: portable, dependencies: dependencies, omittedPluginState: omittedPluginState)
        let content = Content(setlist: portable, dependencies: dependencies, warnings: warnings)
        let data = try SetlistShare.encodeContent(content)
        self.init(format: Self.formatIdentifier, version: Self.supportedVersion, exportedAt: Date(),
                  checksum: AssetDigest.sha256(data), content: content)
    }
}

extension SetlistSharePackage {
    /// Convenience for document readers; all validation stays in `SetlistShare`.
    static func decode(_ data: Data) throws -> SetlistSharePackage { try SetlistShare.decode(data) }
}

/// Portable sharing and import planning. All methods are synchronous and bounded;
/// callers own the UI executor and the local setlist library.
enum SetlistShare {
    static let maximumDependencies = 4096
    static let maximumWarnings = 64
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    static func encodeContent(_ content: SetlistSharePackage.Content) throws -> Data {
        try encoder.encode(content)
    }
    static func encode(_ package: SetlistSharePackage) throws -> Data {
        let data = try encoder.encode(package)
        guard data.count <= SetlistSharePackage.byteLimit else { throw SetlistShareError.tooLarge }
        return data
    }
    static func sealed(_ content: SetlistSharePackage.Content) throws -> SetlistSharePackage {
        let data = try encodeContent(content)
        guard data.count <= SetlistSharePackage.byteLimit else { throw SetlistShareError.tooLarge }
        return SetlistSharePackage(format: SetlistSharePackage.formatIdentifier,
                                   version: SetlistSharePackage.supportedVersion, exportedAt: Date(),
                                   checksum: AssetDigest.sha256(data), content: content)
    }
    static func make(_ setlist: Setlist) throws -> SetlistSharePackage {
        try SetlistSharePackage(source: setlist)
    }
    static func decode(_ data: Data) throws -> SetlistSharePackage {
        guard data.count <= SetlistSharePackage.byteLimit else { throw SetlistShareError.tooLarge }
        let package: SetlistSharePackage
        do { package = try decoder.decode(SetlistSharePackage.self, from: data) }
        catch { throw SetlistShareError.invalidFormat }
        return try reviewed(package)
    }
    static func read(_ url: URL) throws -> SetlistSharePackage {
        guard url.isFileURL else { throw SetlistShareError.invalidFormat }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= SetlistSharePackage.byteLimit else {
            throw SetlistShareError.tooLarge
        }
        return try decode(Data(contentsOf: url))
    }
    static func write(_ setlist: Setlist, to url: URL) throws {
        try write(try make(setlist), to: url)
    }
    static func write(_ package: SetlistSharePackage, to url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "stagekeyssetlist" else {
            throw SetlistShareError.invalidFormat
        }
        try encode(package).write(to: url, options: .atomic)
    }

    /// Full validation of an untrusted package after JSON decoding. The checksum,
    /// format, schema, dependency list and payload exclusions are all checked
    /// before any setlist can be saved or activated.
    static func reviewed(_ package: SetlistSharePackage) throws -> SetlistSharePackage {
        guard package.format == SetlistSharePackage.formatIdentifier else { throw SetlistShareError.invalidFormat }
        guard package.version == SetlistSharePackage.supportedVersion else { throw SetlistShareError.unsupportedVersion }
        guard package.checksum.count == 64, package.checksum.allSatisfy({ $0.isHexDigit }) else {
            throw SetlistShareError.checksum
        }
        let data = try encodeContent(package.content)
        guard data.count <= SetlistSharePackage.byteLimit,
              AssetDigest.sha256(data).caseInsensitiveCompare(package.checksum) == .orderedSame else {
            throw SetlistShareError.checksum
        }
        try validateForExport(package.content.setlist)
        guard !containsPluginState(package.content.setlist) else { throw SetlistShareError.unsafeContent }
        guard package.content.dependencies.count <= maximumDependencies,
              package.content.warnings.count <= maximumWarnings,
              package.content.dependencies.allSatisfy({
                  !$0.name.isEmpty && $0.name.count <= 300 &&
                  !$0.identifier.isEmpty && $0.identifier.count <= 300 &&
                  $0.detail.count <= 500
              }),
              package.content.warnings.allSatisfy({ $0.count <= 500 }),
              package.content.warnings == package.content.warnings.sorted(),
              Set(package.content.dependencies.map(\.id)).count == package.content.dependencies.count,
              package.content.dependencies.map(\.id) == package.content.dependencies.map(\.id).sorted(),
              dependencies(in: package.content.setlist) == package.content.dependencies else {
            throw SetlistShareError.unsafeContent
        }
        return package
    }

    static func validateForExport(_ setlist: Setlist) throws {
        do { try setlist.validate() } catch { throw SetlistShareError.invalidContent }
        guard (1...4).contains(setlist.version), setlist.name.count <= 200 else {
            throw SetlistShareError.invalidContent
        }
    }
    static func containsPluginState(_ setlist: Setlist) -> Bool {
        for patch in setlist.patches {
            if patch.layers.contains(where: { $0.pluginState != nil }) { return true }
            for snapshot in patch.snapshots where snapshot.sounds?.contains(where: { $0.pluginState != nil }) == true {
                return true
            }
        }
        return false
    }
    /// Strip content that is not portable: plug-in document state and local
    /// filesystem locations in user-visible notes. Audio Unit identifiers,
    /// sampler preset names and all authored settings remain.
    static func sanitize(_ setlist: inout Setlist) {
        for p in setlist.patches.indices {
            if let notes = setlist.patches[p].conversionNotes {
                setlist.patches[p].conversionNotes = notes.map(portableText)
            }
            if var tonic = setlist.patches[p].tonicState, let sound = tonic.sound {
                tonic.sound = portable(sound)
                setlist.patches[p].tonicState = tonic
            }
            for l in setlist.patches[p].layers.indices {
                setlist.patches[p].layers[l].pluginState = nil
                if let sound = setlist.patches[p].layers[l].external {
                    setlist.patches[p].layers[l].external = portable(sound)
                }
                if var record = setlist.patches[p].layers[l].mainStageSource {
                    record.sourceNames = record.sourceNames.map(portableText)
                    record.effectNotes = record.effectNotes.map { $0.map(portableText) }
                    record.issues = record.issues.map(portableText)
                    record.omitted = record.omitted.map(portableText)
                    record.retainedShaping = record.retainedShaping.map(portableShaping)
                    setlist.patches[p].layers[l].mainStageSource = record
                }
            }
            for s in setlist.patches[p].snapshots.indices {
                if var sounds = setlist.patches[p].snapshots[s].sounds {
                    for i in sounds.indices { sounds[i].pluginState = nil }
                    setlist.patches[p].snapshots[s].sounds = sounds
                }
            }
        }
    }

    static func dependencies(in setlist: Setlist) -> [SetlistSharePackage.Dependency] {
        var result: [SetlistSharePackage.Dependency] = []
        func add(_ dependency: SetlistSharePackage.Dependency) {
            if !result.contains(where: { $0.id == dependency.id }) { result.append(dependency) }
        }
        func add(_ sound: ExternalSound, tonic: Bool) {
            let name = String((sound.component?.displayName ?? sound.name).prefix(300))
            let identifier = String(identifier(for: sound).prefix(300))
            switch sound.kind {
            case .audioUnit:
                add(.init(kind: .audioUnit, name: name, identifier: identifier,
                          detail: "Install the same Audio Unit on the destination device. Plug-in binaries and saved settings are not included."))
            case .samplerPreset:
                add(.init(kind: tonic ? .tonicPad : .samplerPreset, name: name, identifier: identifier,
                          detail: tonic
                            ? "The Tonic Pad references an imported sampler instrument. Its samples are not included."
                            : "The imported sampler instrument and its referenced samples are not included."))
            case .sample:
                add(.init(kind: .sample, name: name, identifier: identifier,
                          detail: "The referenced sample file is not included."))
            case .soundBank:
                add(.init(kind: .soundBank, name: name, identifier: identifier,
                          detail: "The referenced sound bank is not included; install it on the destination device."))
            }
        }
        for patch in setlist.patches {
            if let sound = patch.tonicState?.sound { add(sound, tonic: true) }
            for layer in patch.layers {
                if let sound = layer.external { add(sound, tonic: false) }
                if let destination = layer.midiDestinationID {
                    add(.init(kind: .externalMIDI, name: String(layer.name.prefix(300)),
                              identifier: String(destination),
                              detail: "The external MIDI destination is device-specific; reselect it after import."))
                }
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    static func warnings(in setlist: Setlist, dependencies: [SetlistSharePackage.Dependency],
                         omittedPluginState: Bool) -> [String] {
        var warnings = Set<String>()
        if omittedPluginState {
            warnings.insert("Saved Audio Unit settings were omitted; the destination device uses its own plug-in state.")
        }
        if dependencies.contains(where: { $0.kind == .audioUnit }) {
            warnings.insert("Audio Units are references only; install the same components on the destination device.")
        }
        if dependencies.contains(where: { [.samplerPreset, .tonicPad, .sample, .soundBank].contains($0.kind) }) {
            warnings.insert("Imported instrument and sample content is not included in this setlist share.")
        }
        if dependencies.contains(where: { $0.kind == .externalMIDI }) {
            warnings.insert("External MIDI destinations are device-specific; reselect them after import.")
        }
        return warnings.sorted()
    }

    /// Plan a destination copy without writing the library or changing the
    /// performance. Available dependencies are checked against this device;
    /// colliding instance identities are replaced while the rest stay stable.
    static func preview(_ package: SetlistSharePackage, library: SetlistLibrary,
                        availability: (ExternalSound) -> String? = { _ in nil }) throws -> SetlistShareImportPlan {
        let reviewed = try reviewed(package)
        var setlist = try reviewed.content.setlist.upgraded()
        let sounds = externalSounds(in: setlist)
        var missing: [SetlistShareImportPlan.Missing] = []
        for dependency in reviewed.content.dependencies where dependency.kind != .externalMIDI {
            guard let sound = sounds.first(where: { identifier(for: $0) == dependency.identifier }) else { continue }
            if let reason = availability(sound), !missing.contains(where: { $0.id == dependency.id }) {
                missing.append(.init(dependency: dependency, reason: reason))
            }
        }
        let inventory = try library.list()
        let existing = inventory.entries.compactMap { try? library.load(id: $0.id) }
        var used = Set<UUID>()
        for item in existing {
            for patch in item.patches {
                used.insert(patch.id)
                patch.layers.forEach { used.insert($0.id) }
                patch.snapshots.forEach { used.insert($0.id) }
            }
        }
        func nextID() -> UUID {
            var value = UUID()
            while used.contains(value) { value = UUID() }
            used.insert(value)
            return value
        }
        var collisions: [String] = []
        for p in setlist.patches.indices {
            if used.contains(setlist.patches[p].id) {
                collisions.append("The patch identity for “\(setlist.patches[p].name)” is already in use; a new identity will be assigned.")
                setlist.patches[p].id = nextID()
            } else { used.insert(setlist.patches[p].id) }
            for l in setlist.patches[p].layers.indices {
                if used.contains(setlist.patches[p].layers[l].id) {
                    collisions.append("A layer identity in “\(setlist.patches[p].name)” is already in use; a new identity will be assigned.")
                    setlist.patches[p].layers[l].id = nextID()
                } else { used.insert(setlist.patches[p].layers[l].id) }
            }
            for s in setlist.patches[p].snapshots.indices {
                if used.contains(setlist.patches[p].snapshots[s].id) {
                    collisions.append("A snapshot identity in “\(setlist.patches[p].name)” is already in use; a new identity will be assigned.")
                    setlist.patches[p].snapshots[s].id = nextID()
                } else { used.insert(setlist.patches[p].snapshots[s].id) }
            }
        }
        let proposedName = uniqueName(setlist.name, existing: inventory.entries.map(\.name))
        setlist.name = proposedName
        try setlist.validate()
        var warnings = reviewed.content.warnings
        if reviewed.content.setlist.version < 4 {
            warnings.append("Setlist schema version \(reviewed.content.setlist.version) will be upgraded to 4 on import.")
        }
        if !missing.isEmpty {
            warnings.append("Save and Load is unavailable until the missing dependencies are installed. Save to Library remains available.")
        }
        warnings = Array(Set(warnings)).sorted().prefix(maximumWarnings).map { $0 }
        return SetlistShareImportPlan(package: reviewed, setlist: setlist,
                                      proposedName: proposedName,
                                      missingDependencies: missing, collisions: collisions, warnings: warnings)
    }

    @discardableResult
    static func saveToLibrary(_ plan: SetlistShareImportPlan, library: SetlistLibrary) throws -> UUID {
        try plan.setlist.validate()
        return try library.save(plan.setlist).id
    }

    private static func externalSounds(in setlist: Setlist) -> [ExternalSound] {
        var result: [ExternalSound] = []
        for patch in setlist.patches {
            if let sound = patch.tonicState?.sound { result.append(sound) }
            for layer in patch.layers {
                if let sound = layer.external { result.append(sound) }
            }
        }
        return result
    }
    private static func identifier(for sound: ExternalSound) -> String {
        sound.kind == .audioUnit ? (sound.component?.id ?? sound.name) : (sound.fileName ?? sound.name)
    }
    private static func portable(_ value: ExternalSound) -> ExternalSound {
        var sound = value
        if var component = sound.component {
            component.unavailableReason = nil
            component.hasCustomView = nil
            component.validated = nil
            component.vendor = nil
            component.version = nil
            sound.component = component
        }
        if var program = sound.nativeSampler {
            program.notes = program.notes.map(portableText)
            sound.nativeSampler = program
        }
        return sound
    }
    /// Replace a whole local path, including spaces and all remaining path
    /// segments, through the end of the line. Absolute and home-relative forms
    /// are both matched; over-redacting the tail is safer than leaving a
    /// home-directory or volume fragment in a shared note.
    private static func portableText(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"(?:file://)?(?:/|~/)[^\n\r]+"#,
            with: "[source location]", options: .regularExpression)
    }
    /// A retained shaping key can itself be a local path, because a file name
    /// such as `/Users/owner/Private/Attack.exs` matches the shaping names. Redact
    /// the key as well as its value, and keep redacted keys distinct.
    private static func portableShaping(_ values: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            let name = portableText(key)
            var candidate = name.isEmpty ? "[source field]" : String(name.prefix(96)), attempt = 0
            while result[candidate] != nil {
                attempt += 1
                let marker = " (\(attempt + 1))"
                candidate = String(name.prefix(max(1, 96 - marker.count))) + marker
            }
            result[candidate] = portableText(value)
        }
        return result
    }
    private static func uniqueName(_ name: String, existing: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Imported Setlist" : String(trimmed.prefix(200))
        var candidate = base, attempt = 0
        while existing.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            attempt += 1
            let marker = attempt == 1 ? " Copy" : " Copy \(attempt)"
            candidate = String(base.prefix(max(1, 200 - marker.count))) + marker
        }
        return candidate
    }
}

/// A plan is read-only until the user chooses an action. `canActivate` is false
/// while any known dependency is unavailable; saving to the library is still
/// allowed so the document is not lost.
struct SetlistShareImportPlan: Identifiable {
    enum Action { case saveAndLoad, saveToLibrary }
    struct Missing: Identifiable {
        let dependency: SetlistSharePackage.Dependency
        let reason: String
        var id: String { dependency.id }
    }
    let id: UUID
    let package: SetlistSharePackage
    let setlist: Setlist
    let proposedName: String
    let missingDependencies: [Missing]
    let collisions: [String]
    let warnings: [String]
    var canActivate: Bool { missingDependencies.isEmpty }

    init(package: SetlistSharePackage, setlist: Setlist, proposedName: String,
         missingDependencies: [Missing], collisions: [String], warnings: [String]) {
        self.id = UUID()
        self.package = package
        self.setlist = setlist
        self.proposedName = proposedName
        self.missingDependencies = missingDependencies
        self.collisions = collisions
        self.warnings = warnings
    }
}

/// Offline share links are optional transport around the same validated package.
/// A link is `stagekeys://setlist-share?package=<base64url(canonical JSON)>`.
/// Hosted services are not required, and no link carries sample or plug-in data.
enum SetlistShareLink {
    static let scheme = "stagekeys"
    static let host = "setlist-share"
    static let maximumDataBytes = 1_500_000
    private static let maximumEncodedCharacters = 2_100_000

    /// Build an offline link from an already validated package. A package can be
    /// valid as a file yet too large for the 1.5 MB link transport.
    static func url(for package: SetlistSharePackage) throws -> URL {
        let data = try SetlistShare.encode(package)
        guard data.count <= maximumDataBytes else { throw SetlistShareError.linkTooLarge }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "package", value: base64URL(data))]
        guard let url = components.url else { throw SetlistShareError.invalidFormat }
        return url
    }
    static func url(for data: Data) throws -> URL {
        try url(for: try SetlistShare.decode(data))
    }
    static func package(from url: URL) throws -> SetlistSharePackage {
        try SetlistShare.decode(try data(from: url))
    }
    static func data(from url: URL) throws -> Data {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host,
              components.path.isEmpty || components.path == "/",
              let items = components.queryItems, items.count == 1,
              items[0].name == "package", let value = items[0].value, !value.isEmpty,
              value.count <= maximumEncodedCharacters,
              let data = decodeBase64URL(value), data.count <= maximumDataBytes else {
            throw SetlistShareError.invalidFormat
        }
        return data
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private static func decodeBase64URL(_ value: String) -> Data? {
        let scalars = value.unicodeScalars
        guard scalars.allSatisfy({
            (48...57).contains($0.value) || (65...90).contains($0.value) ||
            (97...122).contains($0.value) || $0.value == 45 || $0.value == 95
        }) else { return nil }
        var text = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        return Data(base64Encoded: text)
    }
}
