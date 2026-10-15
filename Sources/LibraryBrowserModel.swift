import Foundation

/// Optional user/library tags. Older libraries remain readable without metadata.
struct SoundTags: Codable, Equatable {
    var category: String
    var type: String
    var timbres: [String] = []
    var articulations: [String] = []
    var sourceModel: String = "Sampler"
    var inferred: Bool = false
    static func inferred(name: String, source: String = "Sampler") -> SoundTags {
        let n = name.lowercased()
        let words=Set(n.split(whereSeparator:{!$0.isLetter && !$0.isNumber}).map(String.init))
        let electric=words.contains("electric") || words.contains("roads") || words.contains("tine") || words.contains("ep") || n.hasPrefix("e piano") || n.contains(" e piano")
        var result = SoundTags(category:"Other",type:"Other",sourceModel:source,inferred:true)
        if n.contains("arp") || n.contains("sequence") || n.contains(" seq") { result.category="Arps & Sequences";result.type=n.contains("sequence") || n.contains(" seq") ? "Sequences" : "Melodic Arps";result.articulations=["Arpeggiated"] }
        else if n.contains("bass") {result.category="Bass";result.type="Synth Bass"}
        else if n.contains("pad") || n.contains("soundbed") {result.category="Pads";result.type=n.contains("airy") || n.contains("flute") ? "Airy Pads" : "Synth Pads";result.articulations=["Sustained"]}
        else if n.contains("bell") || n.contains("glass") || n.contains("glock") {result.category="Bells, Glass, Toy Piano";result.type=n.contains("glock") ? "Glockenspiel" : "Bells";result.articulations=["Struck"]}
        else if n.contains("string") || n.contains("violin") {result.category="Strings";result.type="Strings";result.articulations=[n.contains("stacc") ? "Staccato" : "Sustained"]}
        else if n.contains("brass") || n.contains("trombone") {result.category="Brass";result.type="Brass Section";result.articulations=["Blown"]}
        else if n.contains("piano") || n.contains("keys") || n.contains("roads") || n.contains("tine") || words.contains("ep") {result.category="Acoustic Piano & Keys";result.type=n.contains("felt") ? "Felt Piano" : electric ? "Electric Piano" : "Acoustic Piano";result.articulations=["Struck"]}
        else if n.contains("organ") {result.category="Organs";result.type="Organ"}
        else if n.contains("lead") || n.contains("synth") {result.category="Leads";result.type="Synth Leads"}
        for pair in [("warm","Warm"),("bright","Bright"),("soft","Soft"),("dark","Dark"),("airy","Airy"),("retro","Retro"),("clean","Clean"),("shimmer","Shimmer"),("glass","Glassy")] where n.contains(pair.0) {result.timbres.append(pair.1)}
        if n.contains("mono") {result.articulations.append("Monophonic")}
        return result
    }
}
enum LibraryFacet: String, CaseIterable, Identifiable {
    case category="Category", type="Type", timbre="Timbre", articulation="Articulation", library="Sound Library", source="Source/Model", availability="Availability"
    var id:String {rawValue}
}
struct BrowserSound: Identifiable {
    let id:String
    let name:String
    let collection:String
    let tags:SoundTags
    var builtin:Int?
    var entry:LibrarySound?
    var external:ExternalSound?
    var destination:ExternalMIDIDestination?
    var playable:Bool {builtin != nil || entry?.sound != nil || entry?.layer != nil || external != nil || destination != nil}
    func values(_ facet:LibraryFacet)->[String] {
        switch facet {
        case .category:return [tags.category]
        case .type:return [tags.type]
        case .timbre:return tags.timbres
        case .articulation:return tags.articulations
        case .library:return [collection]
        case .source:return [tags.sourceModel]
        case .availability:return [playable ? "Playable" : "Needs Conversion"]
        }
    }
    static func library(_ entry:LibrarySound)->BrowserSound {
        BrowserSound(id:entry.id,name:entry.name,collection:entry.collection,tags:entry.tags ?? .inferred(name:entry.name,source:entry.hostPath != nil ? "MainStage" : entry.sound?.kind == .audioUnit ? "Audio Unit" : "Sampler"),entry:entry)
    }
}
struct LibraryQuery {
    var search=""
    var filters:[LibraryFacet:String]=[:]
    var sort:LibraryFacet?=nil
    var ascending=true
    func matches(_ sound:BrowserSound,ignoring:LibraryFacet?=nil)->Bool {
        let terms=search.split(whereSeparator:{$0.isWhitespace})
        let haystack=([sound.name,sound.collection]+LibraryFacet.allCases.flatMap{sound.values($0)}).joined(separator:" ")
        guard terms.allSatisfy({haystack.localizedCaseInsensitiveContains(String($0))}) else{return false}
        return filters.allSatisfy{facet,value in facet == ignoring || value == "All" || sound.values(facet).contains(value)}
    }
    func results(_ sounds:[BrowserSound])->[BrowserSound] {
        sounds.filter{matches($0)}.sorted {a,b in
            let left=sort.map{a.values($0).joined(separator:", ")} ?? a.name
            let right=sort.map{b.values($0).joined(separator:", ")} ?? b.name
            let comparison=left.localizedStandardCompare(right)
            if comparison == .orderedSame {let tie=a.name.localizedStandardCompare(b.name);return tie == .orderedSame ? a.id < b.id : ascending ? tie == .orderedAscending : tie == .orderedDescending}
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    func options(_ facet:LibraryFacet,in sounds:[BrowserSound])->[String] {
        ["All"]+Set(sounds.filter{matches($0,ignoring:facet)}.flatMap{$0.values(facet)}).filter{!$0.isEmpty}.sorted{$0.localizedStandardCompare($1) == .orderedAscending}
    }
}
