import Foundation
import Darwin

struct LibrarySound: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var collection: String
    var sound: ExternalSound?
    var hostPath: String?
    var layer: Layer?
    var tags: SoundTags?
    var sourceArchiveID: String?
    var conversionNotes: [String]?
    var previousImportedRack: ImportedRack?
    var originalName:String?
    var sourceTagsApplied:Bool?
    var originalInstrument:StageKeysSampler.Original?
}

/// User-owned sounds stay outside the application bundle and survive upgrades.
struct SoundLibrary {
    let url: URL
    /// Compare before commit so a yielding import cannot replace later user edits.
    func commitImport(_ entries:[LibrarySound], replacing original:[LibrarySound]) throws {
        try withExclusiveWrite {
            guard try read() == original else {
                throw MainStagePatch.Failure.invalid("The library changed during import. No prepared sounds were committed; retry to preserve your edits.")
            }
            guard Set(entries.map(\.id)).count == entries.count else {
                throw MainStagePatch.Failure.invalid("Duplicate sound identities in prepared import. No sounds were committed.")
            }
            try writeUnlocked(entries)
        }
    }
    /// Serialize compare-and-write across app processes. Never wait on the UI executor.
    /// The lock file is deliberately retained: unlinking it could create two lock domains.
    private func withExclusiveWrite<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw MainStagePatch.Failure.invalid("Another library operation is in progress. Retry after it finishes; no sounds were committed.")
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
    func read() throws -> [LibrarySound] {
        guard FileManager.default.fileExists(atPath: url.path) ||
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { return [] }
        return try decoded(Self.boundedRead(url,limit:16_000_000))
    }
    private static func boundedRead(_ url:URL,limit:Int)throws->Data {
        try RecoverableSessionFile.read(url,limit:limit)
    }
    private func decoded(_ data:Data)throws->[LibrarySound] {
        guard data.count <= 16_000_000 else { throw CocoaError(.fileReadTooLarge) }
        var entries = try JSONDecoder().decode([LibrarySound].self, from: data)
        for i in entries.indices where entries[i].id.hasPrefix("ableton-samples-") {
            if entries[i].originalName == nil {entries[i].originalName=entries[i].name}
            entries[i].name = Self.cleanImportedName(entries[i].name)
            if var sound = entries[i].sound { sound.name = Self.cleanImportedName(sound.name); entries[i].sound = sound }
            if var layer = entries[i].layer {
                layer.name = Self.cleanImportedName(layer.name)
                if var sound = layer.external { sound.name = Self.cleanImportedName(sound.name); layer.external = sound }
                entries[i].layer = layer
            }
            entries[i].collection = entries[i].collection.replacingOccurrences(of: "Sunday Free Ableton ·", with: "Sunday Free ·")
            if entries[i].collection == "Ableton Imports" { entries[i].collection = "Imported Sounds" }
        }
        for i in entries.indices {
            guard let tags=entries[i].tags,tags.inferred else{continue}
            var updated=SoundTags.inferred(name:entries[i].name,source:tags.sourceModel)
            updated.complexity=tags.complexity;updated.noteRanges=tags.noteRanges;updated.types=tags.types;updated.recommended=tags.recommended
            updated.authoredFacets=tags.authoredFacets
            entries[i].tags=updated
        }
        for i in entries.indices where entries[i].id.hasPrefix("ableton-samples-") {
            var tags=entries[i].tags ?? SoundTags.inferred(name:entries[i].name)
            // These are suggested browsing ranges, never playable MIDI splits.
            // An explicit empty array preserves the user's decision to clear tags.
            if tags.inferred && tags.noteRanges == nil {
                switch tags.category {
                case "Bass":tags.noteRanges=["Left Hand"]
                case "Leads":tags.noteRanges=["Right Hand"]
                case "Pads":tags.noteRanges=["Full Range","Mid Range"]
                case "Arps & Sequences":tags.noteRanges=["Mid Range","Right Hand"]
                default:tags.noteRanges=["Full Range"]
                }
            }
            entries[i].tags=tags
        }
        if let original=entries.first(where:{$0.collection.hasPrefix("Sunday App") && $0.name.hasPrefix("SK App Felt Piano")}),let voiced=SundayFactoryVoicing.feltRoom(from:original) {
            if let index=entries.firstIndex(where:{$0.id==voiced.id}) {
                // Upgrade only our generated variant's missing metadata, preserving edits.
                // An explicit empty array means the user cleared the tags.
                if var tags=entries[index].tags {
                    if tags.noteRanges==nil {tags.noteRanges=voiced.tags?.noteRanges}
                    if tags.types==nil {tags.types=voiced.tags?.types}
                    entries[index].tags=tags
                }
            } else {entries.append(voiced)}
        }
        // Optional personal metadata, never a bundled catalog or sound asset.
        let metadataURL=url.deletingLastPathComponent().appendingPathComponent("source-sound-tags.json")
        if let data=try? Self.boundedRead(metadataURL,limit:2_000_000),
           let metadata=try? JSONDecoder().decode([String:SoundTags].self,from:data) {
            for i in entries.indices where entries[i].collection.hasPrefix("Sunday App") && entries[i].layer != nil {
                guard let authored=metadata[entries[i].name] else{continue}
                var candidate=entries[i];candidate.tags=authored
                guard (try? Self.validate([candidate])) != nil else{continue}
                if entries[i].tags == nil || entries[i].tags?.inferred == true || (entries[i].id.hasSuffix("-room-voicing-v1") && entries[i].sourceTagsApplied != true) {
                    var tags=authored
                    tags.authoredFacets=Self.authoredFacets(for:tags)
                    if let previous=entries[i].tags {
                        // Preserve future per-facet edits and explicit clears; legacy
                        // inferred annotations without provenance remain replaceable.
                        if previous.isAuthored(.noteRange) {
                            tags.noteRanges=previous.noteRanges
                            tags.markAuthored(.noteRange)
                        } else if let ranges=previous.noteRanges,ranges.isEmpty {
                            tags.noteRanges=[]
                            tags.markAuthored(.noteRange)
                        }
                        if previous.isAuthored(.complexity) {
                            tags.complexity=previous.complexity
                            tags.markAuthored(.complexity)
                        }
                        if previous.isAuthored(.type) {
                            tags.types=previous.types
                            tags.markAuthored(.type)
                        }
                        if let recommended=previous.recommended {tags.recommended=recommended}
                    }
                    entries[i].tags=tags;entries[i].sourceTagsApplied=true
                }
                else if var tags=entries[i].tags {
                    // Preserve annotations and explicit clears already saved by the user.
                    if tags.recommended == nil,let value=authored.recommended {tags.recommended=value}
                    if tags.noteRanges == nil,let value=authored.noteRanges {
                        tags.noteRanges=value
                        tags.markAuthored(.noteRange)
                    }
                    if tags.types == nil,let value=authored.types {
                        tags.types=value
                        tags.markAuthored(.type)
                    }
                    entries[i].tags=tags
                }
            }
        }
        try Self.validate(entries); return entries
    }
    static func cleanImportedName(_ name: String) -> String {
        let suffix = " · Ableton Samples"
        var result=name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
        result=result.replacingOccurrences(of:#"\s*[-–—]\s*Sund(?:ay|y) Sounds(?:\s*-\s*\d+)?$"#,with:"",options:[.regularExpression,.caseInsensitive])
        result=result.replacingOccurrences(of:#"\s*[-–—]\s*Layered Patch$"#,with:"",options:[.regularExpression,.caseInsensitive])
        return result.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    func write(_ entries: [LibrarySound]) throws {
        try withExclusiveWrite { try writeUnlocked(entries) }
    }
    private func writeUnlocked(_ entries: [LibrarySound]) throws {
        try Self.validate(entries)
        _ = try read() // A failed startup read must never become an empty overwrite.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(entries)
        guard bytes.count <= 16_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try RecoverableSessionFile.write(bytes,to:url,limit:16_000_000) { _ = try decoded($0) }
    }
    func recoverPrevious()throws->[LibrarySound] {
        try withExclusiveWrite {
            let data=try RecoverableSessionFile.restore(url,limit:16_000_000) { _ = try decoded($0) }
            return try decoded(data)
        }
    }
    /// Metadata declares only the facets it can substantiate. An explicit
    /// "Not Tagged" source or a missing optional facet stays unknown.
    private static func authoredFacets(for tags:SoundTags)->[String] {
        LibraryFacet.tagFacets.compactMap { facet in
            switch facet {
            case .category:return tags.category.isEmpty ? nil:facet.rawValue
            case .type:return tags.type.isEmpty && (tags.types?.isEmpty ?? true) ? nil:facet.rawValue
            case .timbre:return tags.timbres.isEmpty ? nil:facet.rawValue
            case .articulation:return tags.articulations.isEmpty ? nil:facet.rawValue
            case .source:return tags.sourceModel == "Not Tagged" ? nil:facet.rawValue
            case .complexity:return tags.complexity == nil ? nil:facet.rawValue
            case .noteRange:return tags.noteRanges == nil ? nil:facet.rawValue
            default:return nil
            }
        }
    }
    static func validate(_ entries: [LibrarySound]) throws {
        guard entries.count <= 4096, Set(entries.map(\.id)).count == entries.count else { throw SetlistError.invalid }
        for entry in entries {
            guard !entry.id.isEmpty, entry.id.count <= 256, !entry.name.isEmpty, entry.name.count <= 200, entry.collection.count <= 200 else { throw SetlistError.invalid }
            if let original=entry.originalInstrument {
                guard original.sha256.count==64,original.sha256.allSatisfy({$0.isHexDigit && !$0.isUppercase}),
                      ["exs","aupreset"].contains(URL(fileURLWithPath:original.file).pathExtension),
                      original.file=="Original Instruments/"+original.sha256+"."+URL(fileURLWithPath:original.file).pathExtension else{throw SetlistError.invalid}
            }
            if let previous=entry.previousImportedRack, !previous.validate() {throw SetlistError.invalid}
            if let notes=entry.conversionNotes {guard notes.count<=128,notes.allSatisfy({$0.count<=2000}) else{throw SetlistError.invalid}}
            if let tags=entry.tags {
                guard tags.complexity.map({["Simple","Moderate","Complex"].contains($0)}) ?? true else{throw SetlistError.invalid}
                guard tags.noteRanges.map({$0.count<=4 && Set($0).count==$0.count && $0.allSatisfy{LibraryNoteRange(rawValue:$0) != nil}}) ?? true else{throw SetlistError.invalid}
                guard tags.types.map({$0.count<=64 && Set($0).count==$0.count && $0.allSatisfy{!$0.isEmpty && $0.count<=200}}) ?? true else{throw SetlistError.invalid}
                let text=[tags.category,tags.type,tags.sourceModel]+tags.timbres+tags.articulations
                guard tags.timbres.count<=64,tags.articulations.count<=64,text.allSatisfy({$0.count<=200}) else {throw SetlistError.invalid}
                if let authored=tags.authoredFacets {
                    guard authored.count<=LibraryFacet.tagFacets.count,
                          Set(authored).count==authored.count,
                          authored.allSatisfy({LibraryFacet(rawValue:$0)?.isTagFacet == true}) else{throw SetlistError.invalid}
                }
            }
            if let source=entry.sourceArchiveID {guard !source.isEmpty,source.count<=256 else{throw SetlistError.invalid}}
            if let layer = entry.layer {
                guard layer.loaded || layer.instrument >= 0 else { throw SetlistError.invalid } // Retain legacy metadata; it is not a playable source.
                var validation = Setlist(); validation.patches = [Patch(name:"Saved Sound",layers:[layer],snapshots:[])]; try validation.validate()
            } else if let sound = entry.sound {
                var layer = Layer(name:entry.name,instrument:-1,gain:0.5); layer.external=sound
                var validation = Setlist(); validation.patches = [Patch(name:"Saved Sound",layers:[layer],snapshots:[])]; try validation.validate()
            } else { guard let path = entry.hostPath, path.hasPrefix("/"), path.count <= 16_384 else { throw SetlistError.invalid } }
        }
    }
}

extension SoundLibrary {
    static func samplerPresets(in root: URL) throws -> [URL] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw CocoaError(.fileReadNoPermission) }
        var presets: [URL] = []; var visited = 0
        for case let url as URL in files {
            visited += 1
            guard visited <= 20_000 else { throw CocoaError(.fileReadTooLarge) }
            if files.level > 16 { files.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { files.skipDescendants(); continue }
            if values.isRegularFile == true && ["aupreset", "exs"].contains(url.pathExtension.lowercased()) {
                presets.append(url)
                guard presets.count <= 256 else { throw CocoaError(.fileReadTooLarge) }
            }
        }
        return presets.sorted { $0.path < $1.path }
    }
}
