import Foundation
import AVFoundation
import AudioToolbox

/// Loading journal only; no plug-in state or user session content is stored.
final class PluginLoadRecovery {
    private struct Record: Codable {var pending:[String:Int]=[:];var blocked:Set<String>=[]}
    private var record:Record
    private let url:URL
    init(url:URL)throws {
        self.url=url
        if FileManager.default.fileExists(atPath:url.path) {
            let data=try Data(contentsOf:url)
            guard data.count<=1_000_000 else{throw ExternalInstrumentError.invalidComponent}
            record=try JSONDecoder().decode(Record.self,from:data)
        } else {record=Record()}
        record.blocked.formUnion(record.pending.keys);record.pending=[:]
        try save()
    }
    private func save()throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(record).write(to:url,options:.atomic)
    }
    func isBlocked(_ id:String)->Bool {record.blocked.contains(id)}
    func begin(_ id:String)throws {
        guard !isBlocked(id) else{throw NSError(domain:"StageKeysPluginRecovery",code:1,userInfo:[NSLocalizedDescriptionKey:"This Audio Unit is blocked after a failed or interrupted load. Use Allow Blocked Loads in the Audio Units browser to retry explicitly."])}
        record.pending[id,default:0]+=1;try save()
    }
    func finish(_ id:String,failed:Bool)throws {
        let remaining=max(0,(record.pending[id] ?? 1)-1)
        if remaining==0 {record.pending[id]=nil} else {record.pending[id]=remaining}
        if failed {record.blocked.insert(id)}
        try save()
    }
    func allowBlockedLoads()throws {record.blocked=[];try save()}
}

/// Persisted, portable component identity; installation remains a device requirement.
/// Display metadata from the component catalog is presentation only: equality and
/// hashing use the component triple and display name, so enriching a saved layer
/// with vendor/version details never causes a needless instrument reload.
struct ExternalAUIdentity: Codable, Hashable, Identifiable {
    var type: UInt32
    var subtype: UInt32
    var manufacturer: UInt32
    var name: String
    var vendor: String? = nil
    var version: String? = nil
    var isV3: Bool? = nil
    var hasCustomView: Bool? = nil
    var validated: Bool? = nil
    var unavailableReason: String? = nil
    var id: String { "\(type)-\(subtype)-\(manufacturer)" }
    var isAvailable: Bool { unavailableReason == nil }
    var displayName: String { vendor.map { "\(name) — \($0)" } ?? name }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && lhs.subtype == rhs.subtype && lhs.manufacturer == rhs.manufacturer && lhs.name == rhs.name
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(type); hasher.combine(subtype); hasher.combine(manufacturer); hasher.combine(name)
    }
}

/// Catalog ordering and search for installed Audio Units. Kept separate from
/// Core Audio enumeration so it can be verified without third-party plug-ins.
enum ExternalAUCatalog {
    /// Vendor first, then display name, then the stable component identity.
    static func sorted(_ items: [ExternalAUIdentity]) -> [ExternalAUIdentity] {
        items.sorted { lhs, rhs in
            let left = lhs.vendor ?? "", right = rhs.vendor ?? ""
            if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
    /// Matches the browser search contract: every whitespace-separated term must
    /// appear in the name or vendor, so "arturia jun" finds an Arturia Jun-6.
    static func matches(_ identity: ExternalAUIdentity, query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return true }
        let haystack = [identity.name, identity.vendor ?? "", identity.version ?? ""].joined(separator: " ")
        return terms.allSatisfy { haystack.localizedCaseInsensitiveContains(String($0)) }
    }
}

struct ExternalSound: Codable, Hashable {
    enum Kind: String, Codable { case soundBank, sample, samplerPreset, audioUnit }
    var kind: Kind
    var name: String
    var fileName: String? = nil
    var component: ExternalAUIdentity? = nil
    var program: UInt8 = 0
    var bankMSB: UInt8 = 121
    var bankLSB: UInt8 = 0
    var nativeSampler:NativeSamplerProgram?
}


/// Converted instruments use resident samples on Mac: the streamed multi-bank
/// graph can introduce discontinuities absent from offline/resident playback.
/// Only active instruments are loaded; original sample files remain untouched.
enum SamplerRendering {
    static func configure(_ sampler:AVAudioUnitSampler,offline:Bool,resident:Bool=false)throws {
        var properties:[(AudioUnitPropertyID,UInt32)]=[]
        if offline {properties.append((kAudioUnitProperty_OfflineRender,UInt32(1)))}
        #if os(macOS)
        if offline || resident {properties.insert((kMusicDeviceProperty_StreamFromDisk,0),at:0)}
        #endif
        for (property,value) in properties {
            var setting=value
            let status=AudioUnitSetProperty(sampler.audioUnit,property,kAudioUnitScope_Global,0,&setting,UInt32(MemoryLayout<UInt32>.size))
            guard status==noErr else{throw NSError(domain:NSOSStatusErrorDomain,code:Int(status))}
        }
    }
}
