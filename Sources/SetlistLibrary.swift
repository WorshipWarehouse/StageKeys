import Foundation

/// Last-known-good session bytes. Call only on the serialized persistence executor.
enum RecoverableSessionFile {
    static func previous(_ url: URL) -> URL { url.appendingPathExtension("previous") }
    static func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 64_000_000 else { throw SetlistLibraryError.unsafeFile }
        let data = try Data(contentsOf: url)
        guard data.count <= 64_000_000 else { throw SetlistLibraryError.oversized }
        return data
    }
    static func write(_ data: Data, to url: URL, validate: (Data) throws -> Void) throws {
        try validate(data)
        guard data.count <= 64_000_000 else { throw SetlistLibraryError.oversized }
        if FileManager.default.fileExists(atPath: url.path) {
            let old = try read(url)
            try validate(old) // Never rotate corrupt or future-version data over the recovery copy.
            if old != data { try old.write(to: previous(url), options: .atomic) }
        }
        try data.write(to: url, options: .atomic)
    }
    static func restore(_ url: URL, validate: (Data) throws -> Void) throws -> Data {
        let recovered = try read(previous(url))
        try validate(recovered)
        if FileManager.default.fileExists(atPath: url.path) {
            let damaged = try read(url)
            try damaged.write(to: url.appendingPathExtension("damaged-" + UUID().uuidString), options: .atomic)
        }
        try recovered.write(to: url, options: .atomic)
        return recovered
    }
}

struct SetlistLibraryDescriptor: Identifiable, Equatable {
    let id: UUID
    let name: String
    let patchCount: Int
    let modifiedDate: Date
}
struct SetlistLibraryIssue: Equatable {
    let fileName: String
    let message: String
}
struct SetlistLibraryInventory {
    var entries: [SetlistLibraryDescriptor]
    var issues: [SetlistLibraryIssue]
}
struct SetlistTrashEntry: Identifiable, Equatable {
    let token: UUID
    let originalID: UUID
    let name: String
    let deletedDate: Date
    var id: UUID { token }
}
struct SetlistTrashInventory {
    var entries: [SetlistTrashEntry]
    var issues: [SetlistLibraryIssue]
}
enum SetlistLibraryError: LocalizedError {
    case full, oversized, unsafeFile, name, restoreConflict
    var errorDescription: String? {
        switch self {
        case .full: return "The local library holds up to 128 setlists. Move a setlist to Trash before adding another."
        case .oversized: return "This setlist exceeds the 64 MB file limit."
        case .unsafeFile: return "The setlist file is not a regular local library file."
        case .name: return "Enter a setlist name of 1–200 characters."
        case .restoreConflict: return "The original setlist identity is already in use. Duplicate or rename it before restoring."
        }
    }
}

/// A caller-owned local repository. Access serially on one executor. Invalid
/// files remain on disk and are reported; deletion always creates a Trash record.
final class SetlistLibrary {
    let root: URL
    private let manager = FileManager.default
    private let byteLimit = 64 * 1024 * 1024
    private var trash: URL { root.appendingPathComponent("Trash", isDirectory: true) }
    private struct TrashRecord: Codable {
        let token: UUID
        let originalID: UUID
        let deletedDate: Date
        let setlist: Setlist
    }
    init(root: URL) throws {
        guard root.isFileURL else { throw SetlistLibraryError.unsafeFile }
        let requestedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: true)
        // Foundation normalizes /private/tmp differently once a previously
        // missing directory exists. Pin the canonical path after creation.
        self.root = requestedRoot.resolvingSymlinksInPath().standardizedFileURL
        try manager.createDirectory(at: trash, withIntermediateDirectories: true)
        guard trash.resolvingSymlinksInPath().standardizedFileURL.path == trash.path else { throw SetlistLibraryError.unsafeFile }
    }
    private func file(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".json") }
    private func trashFile(_ token: UUID) -> URL { trash.appendingPathComponent(token.uuidString + ".json") }
    private func candidates(_ directory: URL) throws -> [URL] {
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path else { throw SetlistLibraryError.unsafeFile }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension.lowercased() == "json" }
    }
    private func bytes(_ url: URL, directory: URL) throws -> Data {
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path,
              url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else { throw SetlistLibraryError.unsafeFile }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw SetlistLibraryError.unsafeFile }
        guard (values.fileSize ?? Int.max) <= byteLimit else { throw SetlistLibraryError.oversized }
        let data = try Data(contentsOf: url)
        guard data.count <= byteLimit else { throw SetlistLibraryError.oversized }
        return data
    }
    private func descriptor(_ setlist: Setlist, id: UUID, url: URL) throws -> SetlistLibraryDescriptor {
        SetlistLibraryDescriptor(id: id, name: setlist.name, patchCount: setlist.patches.count,
            modifiedDate: try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
    }
    func list() throws -> SetlistLibraryInventory {
        var result = SetlistLibraryInventory(entries: [], issues: [])
        for url in try candidates(root) {
            do {
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw SetlistLibraryError.unsafeFile }
                let setlist = try JSONDecoder().decode(Setlist.self, from: bytes(url, directory: root)).upgraded()
                result.entries.append(try descriptor(setlist, id: id, url: url))
            } catch { result.issues.append(SetlistLibraryIssue(fileName: url.lastPathComponent, message: error.localizedDescription)) }
        }
        result.entries.sort { $0.modifiedDate == $1.modifiedDate ? $0.id.uuidString < $1.id.uuidString : $0.modifiedDate > $1.modifiedDate }
        result.issues.sort { $0.fileName < $1.fileName }
        return result
    }
    func load(id: UUID) throws -> Setlist {
        try JSONDecoder().decode(Setlist.self, from: bytes(file(id), directory: root)).upgraded()
    }
    @discardableResult
    func save(_ setlist: Setlist, id existingID: UUID? = nil) throws -> SetlistLibraryDescriptor {
        let upgraded = try setlist.upgraded()
        let id = existingID ?? UUID()
        let target = file(id)
        guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else { throw SetlistLibraryError.unsafeFile }
        guard (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SetlistLibraryError.unsafeFile }
        let exists = manager.fileExists(atPath: target.path)
        if exists { _ = try bytes(target, directory: root) }
        else if try candidates(root).filter({ UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }).count >= 128 { throw SetlistLibraryError.full }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(upgraded)
        guard data.count <= byteLimit else { throw SetlistLibraryError.oversized }
        try data.write(to: target, options: .atomic)
        return try descriptor(upgraded, id: id, url: target)
    }
    @discardableResult
    func rename(id: UUID, name: String) throws -> SetlistLibraryDescriptor {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { throw SetlistLibraryError.name }
        var setlist = try load(id: id)
        setlist.name = title
        return try save(setlist, id: id)
    }
    @discardableResult
    func duplicate(id: UUID, name: String? = nil) throws -> SetlistLibraryDescriptor {
        var copy = try load(id: id)
        let title = name ?? (copy.name + " Copy")
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200 else { throw SetlistLibraryError.name }
        copy.name = title
        copy.patches = copy.patches.map { source in
            var patch = source.duplicate()
            patch.name = source.name
            return patch
        }
        return try save(copy)
    }
    @discardableResult
    func delete(id: UUID) throws -> SetlistTrashEntry {
        let setlist = try load(id: id)
        let record = TrashRecord(token: UUID(), originalID: id, deletedDate: Date(), setlist: setlist)
        let data = try JSONEncoder().encode(record)
        guard data.count <= byteLimit else { throw SetlistLibraryError.oversized }
        guard trash.resolvingSymlinksInPath().standardizedFileURL.path == trash.path else { throw SetlistLibraryError.unsafeFile }
        try data.write(to: trashFile(record.token), options: .atomic)
        // Original removal happens only after the validated recoverable record
        // has been fully written. Failure keeps both copies, never loses data.
        try manager.removeItem(at: file(id))
        return SetlistTrashEntry(token: record.token, originalID: id, name: setlist.name, deletedDate: record.deletedDate)
    }
    private func trashRecord(_ token: UUID) throws -> TrashRecord {
        let record = try JSONDecoder().decode(TrashRecord.self, from: bytes(trashFile(token), directory: trash))
        guard record.token == token else { throw SetlistLibraryError.unsafeFile }
        try record.setlist.validate()
        return record
    }
    func listTrash() throws -> SetlistTrashInventory {
        var result = SetlistTrashInventory(entries: [], issues: [])
        for url in try candidates(trash) {
            do {
                guard let token = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw SetlistLibraryError.unsafeFile }
                let record = try trashRecord(token)
                result.entries.append(SetlistTrashEntry(token: token, originalID: record.originalID, name: record.setlist.name, deletedDate: record.deletedDate))
            } catch { result.issues.append(SetlistLibraryIssue(fileName: url.lastPathComponent, message: error.localizedDescription)) }
        }
        result.entries.sort { $0.deletedDate > $1.deletedDate }
        return result
    }
    @discardableResult
    func restore(token: UUID) throws -> SetlistLibraryDescriptor {
        let record = try trashRecord(token)
        guard !manager.fileExists(atPath: file(record.originalID).path) else { throw SetlistLibraryError.restoreConflict }
        let restored = try save(record.setlist, id: record.originalID)
        // Keep the Trash record as an additional recovery copy. Restore never
        // permanently removes the user's only historical backup.
        return restored
    }
}
