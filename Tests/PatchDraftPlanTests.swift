import Foundation

@main struct PatchDraftPlanTests {
    static func main() throws {
        var original=TestFixtures.layer(1,gain:0.2,name:"Authorized Pad")
        original.effects[0]=AudioEffect.factoryDefault(kind:13)
        let entry=LibrarySound(id:"owned-pad",name:original.name,collection:"My Sounds",layer:original)
        let plan=PatchDraftPlan(name:"Local Draft",sounds:[.init(libraryID:entry.id,gain:0.3,pan:-0.2,low:48,high:96)])
        let preview=try plan.preview(library:[entry],available:{_ in true})
        assert(preview.patch?.layers.count==15 && preview.patch?.layers[0].effects==original.effects)
        assert(preview.patch?.layers[0].id != original.id && original.gain==0.2)
        let decoded=try JSONDecoder().decode(PatchDraftPlan.self,from:JSONEncoder().encode(plan))
        assert(try! decoded.preview(library:[],available:{_ in true}).missingSoundIDs==[entry.id])
        var invalid=plan;invalid.sounds[0].gain = .nan
        do {_ = try invalid.preview(library:[entry],available:{_ in true});assertionFailure("Invalid generated gain accepted")}catch{}
        invalid=plan;invalid.sounds.append(invalid.sounds[0])
        do {_ = try invalid.preview(library:[entry],available:{_ in true});assertionFailure("Duplicate generated sound accepted")}catch{}
        var unavailable=entry;unavailable.layer!.external=ExternalSound(kind:.samplerPreset,name:"Missing",fileName:"missing.aupreset")
        let missing=try plan.preview(library:[unavailable],available:{_ in false})
        assert(missing.patch==nil && missing.missingSoundIDs==[entry.id])
        print("PASS: local draft resolves only authorized library IDs, validates bounded settings, reports missing content and never mutates source layers")
    }
}
