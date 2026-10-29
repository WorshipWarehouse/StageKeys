import Foundation

/// Optional user/library tags. Older libraries remain readable without metadata.
struct SoundTags: Codable, Equatable {
    var category: String
    var type: String
    var timbres: [String] = []
    var articulations: [String] = []
    var sourceModel: String = "Sampler"
    var inferred: Bool = false
    var complexity:String?
    var noteRanges:[String]?
    var types:[String]?
    var recommended:Bool?
    static func inferred(name: String, source: String = "Sampler") -> SoundTags {
        let n = name.replacingOccurrences(of:"([a-z])([A-Z])",with:"$1 $2",options:.regularExpression).lowercased()
        let words=Set(n.split(whereSeparator:{!$0.isLetter && !$0.isNumber}).map(String.init))
        let electric=words.contains("electric") || words.contains("roads") || words.contains("rhodes") || words.contains("wurli") || words.contains("wurlitzer") || words.contains("tine") || words.contains("ep") || n.hasPrefix("e piano") || n.contains(" e piano")
        var result = SoundTags(category:"Other",type:"Other",sourceModel:source,inferred:true)
        let sequenced = !words.isDisjoint(with:["sequence","sequences","sequenced","seq"])
        if sequenced || !words.isDisjoint(with:["arp","arps","arpeggio","arpeggios","arpeggiated"]) { result.category="Arps & Sequences";result.type=sequenced ? "Sequences" : "Melodic Arps";result.articulations=["Arpeggiated"] }
        else if !words.isDisjoint(with:["bass","basses"]) {result.category="Bass";result.type="Synth Bass"}
        else if n.contains("pad") || n.contains("soundbed") {result.category="Pads";result.type=n.contains("airy") || n.contains("flute") ? "Airy Pads" : "Synth Pads";result.articulations=["Sustained"]}
        else if n.contains("bell") || n.contains("glass") || n.contains("glock") {result.category="Bells, Glass, Toy Piano";result.type=n.contains("glock") ? "Glockenspiel" : "Bells";result.articulations=["Struck"]}
        else if n.contains("string") || n.contains("violin") {result.category="Strings";result.type="Strings";result.articulations=[n.contains("stacc") ? "Staccato" : "Sustained"]}
        else if n.contains("brass") || n.contains("trombone") {result.category="Brass";result.type="Brass Section";result.articulations=["Blown"]}
        else if electric || n.contains("piano") || n.contains("keys") || n.contains("roads") || n.contains("tine") || words.contains("ep") {result.category="Acoustic Piano & Keys";result.type=n.contains("felt") ? "Felt Piano" : electric ? "Electric Piano" : "Acoustic Piano";result.articulations=["Struck"]}
        else if !words.isDisjoint(with:["organ","organs"]) {result.category="Organs";result.type="Organ"}
        else if n.contains("guitar") || n.contains("telecaster") {result.category="Guitars";result.type="Electric Guitar";result.articulations=["Plucked"]}
        else if n.contains("pluck") || n.contains("pizz") {result.category="Leads";result.type="Synth Plucks";result.articulations=["Plucked"]}
        else if n.contains("lead") || n.contains("synth") {result.category="Leads";result.type="Synth Leads"}
        for pair in [("warm","Warm"),("bright","Bright"),("soft","Soft"),("dark","Dark"),("airy","Airy"),("retro","Retro"),("clean","Clean"),("shimmer","Shimmer"),("glass","Glassy")] where n.contains(pair.0) {result.timbres.append(pair.1)}
        if words.contains("mono") || words.contains("monophonic") {result.articulations.append("Monophonic")}
        return result
    }
}
enum LibraryNoteRange:String,CaseIterable {
    case full="Full Range",left="Left Hand",mid="Mid Range",right="Right Hand"
    static func toggling(_ range:Self,in values:[String]?)->[String] {
        var selected=Set(values ?? [])
        if selected.contains(range.rawValue) {selected.remove(range.rawValue)} else {selected.insert(range.rawValue)}
        return allCases.map(\.rawValue).filter{selected.contains($0)}
    }
}
enum LibraryFacet: String, CaseIterable, Identifiable {
    case category="Category", type="Type", timbre="Timbre", articulation="Articulation", library="Sound Library", source="Source/Model", availability="Availability", complexity="Complexity",noteRange="Note Range"
    var id:String {rawValue}
}
struct BrowserSound: Identifiable {
    let id:String
    let name:String
    let collection:String
    let tags:SoundTags
    var entry:LibrarySound?
    var external:ExternalSound?
    var destination:ExternalMIDIDestination?
    var rating=0
    var addedOrder=0
    /// Set for installed Audio Units that cannot be hosted on this machine, and
    /// for reporting that a component has not passed auval.
    var unavailableReason:String?
    var validationNote:String?
    var ratingID:String {entry?.id ?? id}
    var playable:Bool {(entry?.sound != nil || entry?.layer?.loaded == true || external != nil || destination != nil) && unavailableReason == nil}
    func values(_ facet:LibraryFacet)->[String] {
        switch facet {
        case .noteRange:return tags.noteRanges?.isEmpty == false ? tags.noteRanges!:["Not Tagged"]
        case .complexity:return [tags.complexity ?? "Not Tagged"]
        case .category:return [tags.category]
        case .type:return Array(Set([tags.type]+(tags.types ?? []))).sorted()
        case .timbre:return tags.timbres.isEmpty ? ["Not Tagged"]:tags.timbres
        case .articulation:return tags.articulations.isEmpty ? ["Not Tagged"]:tags.articulations
        case .library:return [collection]
        case .source:return [tags.sourceModel]
        case .availability:return [unavailableReason != nil ? "Unavailable" : playable ? "Playable" : "Needs Conversion"]
        }
    }
    static func archive(_ original:LibrarySound,converted:LibrarySound)->BrowserSound {
        let playable=library(converted)
        var tags=original.tags ?? playable.tags
        // Row annotations belong to the playable entry, shared across collections.
        tags.noteRanges=playable.tags.noteRanges;tags.complexity=playable.tags.complexity;tags.types=playable.tags.types;tags.recommended=playable.tags.recommended
        return BrowserSound(id:original.id,name:original.name,collection:original.collection,tags:tags,entry:converted)
    }
    static func library(_ entry:LibrarySound)->BrowserSound {
        var sound=BrowserSound(id:entry.id,name:entry.name,collection:entry.collection,tags:entry.tags ?? .inferred(name:entry.name,source:entry.hostPath != nil ? "MainStage" : entry.sound?.kind == .audioUnit ? "Audio Unit" : "Sampler"),entry:entry)
        if let layer=entry.layer,entry.sound==nil,!layer.loaded,layer.instrument>=0 {sound.unavailableReason="Legacy voice unavailable. Import a replacement sound; saved settings are retained."}
        return sound
    }
}
enum LibrarySort:String,CaseIterable {case name="Name",recommended="Recommended",rating="Rating",recent="Recently Added",random="Random"}
struct LibraryQuery {
    var search=""
    var filters:[LibraryFacet:String]=[:]
    var sort:LibraryFacet?=nil
    var ascending=true
    var ordering:LibrarySort = .name
    var shuffleSeed:UInt64=0
    mutating func order(by mode:LibrarySort) {
        ordering=mode;sort=nil;ascending=mode == .name || mode == .recommended
        if mode == .random {shuffleSeed=UInt64.random(in:1...UInt64.max)}
    }
    private func randomKey(_ id:String)->UInt64 {
        // Stable within a browsing session and independent of process hash seeds.
        var h:UInt64=14695981039346656037 ^ shuffleSeed
        for byte in id.utf8 {h=(h ^ UInt64(byte)) &* 1099511628211}
        h ^= h >> 30;h &*= 0xbf58476d1ce4e5b9;h ^= h >> 27;h &*= 0x94d049bb133111eb;return h ^ (h >> 31)
    }
    func matches(_ sound:BrowserSound,ignoring:LibraryFacet?=nil)->Bool {
        let terms=search.split(whereSeparator:{$0.isWhitespace})
        let haystack=([sound.name,sound.collection]+LibraryFacet.allCases.flatMap{sound.values($0)}).joined(separator:" ")
        guard terms.allSatisfy({haystack.localizedCaseInsensitiveContains(String($0))}) else{return false}
        return filters.allSatisfy{facet,value in facet == ignoring || value == "All" || sound.values(facet).contains(value)}
    }
    func results(_ sounds:[BrowserSound])->[BrowserSound] {
        sounds.filter{matches($0)}.sorted {a,b in
            if sort == nil && ordering != .name {
                let left:UInt64,right:UInt64
                switch ordering {
                case .recommended:left=a.tags.recommended == true ? 0:1;right=b.tags.recommended == true ? 0:1
                case .rating:left=UInt64(max(0,a.rating));right=UInt64(max(0,b.rating))
                case .recent:left=UInt64(max(0,a.addedOrder));right=UInt64(max(0,b.addedOrder))
                case .random:left=randomKey(a.id);right=randomKey(b.id)
                case .name:left=0;right=0
                }
                if left != right {return ascending ? left<right:left>right}
            }
            let left=sort.map{a.values($0).joined(separator:", ")} ?? a.name
            let right=sort.map{b.values($0).joined(separator:", ")} ?? b.name
            let comparison=left.localizedStandardCompare(right)
            if comparison == .orderedSame {let tie=a.name.localizedStandardCompare(b.name);return tie == .orderedSame ? a.id < b.id : ascending ? tie == .orderedAscending : tie == .orderedDescending}
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    func options(_ facet:LibraryFacet,in sounds:[BrowserSound])->[String] {
        if facet == .noteRange {
            // The source retains all four choices even after narrowing by type.
            let unknown=filters[facet]=="Not Tagged" || sounds.filter{matches($0,ignoring:facet)}.contains{$0.values(.noteRange).contains("Not Tagged")}
            return ["All"]+LibraryNoteRange.allCases.map(\.rawValue)+(unknown ? ["Not Tagged"]:[])
        }
        var values=Set(sounds.filter{matches($0,ignoring:facet)}.flatMap{$0.values(facet)})
        if let selected=filters[facet],selected != "All" {values.insert(selected)}
        return ["All"]+values.filter{!$0.isEmpty}.sorted{$0.localizedStandardCompare($1) == .orderedAscending}
    }
}

/// Personal ratings are independent of samples, sound presets and patch snapshots.
enum SoundRatingArchive {
    static func valid(_ ratings:[String:Int])->Bool {ratings.count<=8192 && ratings.allSatisfy{!$0.key.isEmpty && $0.key.count<=512 && (1...5).contains($0.value)}}
    static func load(_ url:URL)->[String:Int] {
        (try? read(url)) ?? [:]
    }
    private static func decoded(_ data:Data)throws->[String:Int] {
        guard data.count<=4_000_000 else{throw SetlistLibraryError.oversized}
        let ratings=try JSONDecoder().decode([String:Int].self,from:data)
        guard valid(ratings) else{throw SetlistError.invalid}
        return ratings
    }
    static func read(_ url:URL)throws->[String:Int] {
        guard FileManager.default.fileExists(atPath:url.path) || (try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true else{return [:]}
        return try decoded(RecoverableSessionFile.read(url,limit:4_000_000))
    }
    static func recover(_ url:URL)throws->[String:Int] {
        try decoded(RecoverableSessionFile.restore(url,limit:4_000_000){_ = try decoded($0)})
    }
    static func setting(_ value:Int,for id:String,in ratings:[String:Int])->[String:Int]? {
        guard !id.isEmpty,id.count<=512,(0...5).contains(value) else{return nil}
        var updated=ratings;updated[id]=value==0 ? nil:value
        return valid(updated) ? updated:nil
    }
    static func save(_ ratings:[String:Int],to url:URL)throws {
        guard valid(ratings) else{throw CocoaError(.fileWriteInvalidFileName)}
        _ = try read(url)
        let data=try JSONEncoder().encode(ratings)
        guard data.count<=4_000_000 else{throw CocoaError(.fileWriteOutOfSpace)}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try RecoverableSessionFile.write(data,to:url,limit:4_000_000){_ = try decoded($0)}
    }
}
