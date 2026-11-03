import Foundation

/// Repair rules for library sounds whose managed file moved or was lost.
/// Detection and repair are identity-checked and must never destroy the bytes
/// that are still present or publish an unverified replacement.
@main struct LibraryRepairTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let library=root.appendingPathComponent("Imported Sounds")
        let source=root.appendingPathComponent("Moved Sound.aupreset")
        let bytes=Data("preset bytes".utf8)
        try bytes.write(to:source)

        // A verified copy becomes a managed file with the entry's stored name.
        var verified=0
        try LibraryAssetRepair.restore(named:"Moved Sound.aupreset",from:source,to:library) { temporary in
            verified+=1
            assert(temporary.lastPathComponent.hasPrefix(".repair-"),"The copy is staged under a temporary name")
            assert(temporary.deletingLastPathComponent().standardizedFileURL==library.standardizedFileURL,"The staged copy stays in the managed folder")
            assert((try! Data(contentsOf:temporary))==bytes)
        }
        assert(verified==1)
        assert((try! Data(contentsOf:library.appendingPathComponent("Moved Sound.aupreset")))==bytes)
        assert((try! Data(contentsOf:source))==bytes,"The located original is not moved or altered")
        let staged=try FileManager.default.contentsOfDirectory(atPath:library.path).filter{$0.hasPrefix(".repair-")}
        assert(staged.isEmpty,"No staging file is left behind")

        // An existing managed file is never overwritten by a later repair.
        do {try LibraryAssetRepair.restore(named:"Moved Sound.aupreset",from:source,to:library){_ in};fatalError("Existing managed file was replaced")}
        catch LibraryAssetRepair.Failure.alreadyPresent {}
        assert((try! Data(contentsOf:library.appendingPathComponent("Moved Sound.aupreset")))==bytes)

        // A name that could address outside the managed folder is refused.
        for name in ["../escape.aupreset","nested/thing.aupreset","",".hidden",String(repeating:"a",count:201)] {
            do {try LibraryAssetRepair.restore(named:name,from:source,to:library){_ in};fatalError("Unsafe name accepted: \(name)")}
            catch LibraryAssetRepair.Failure.unsafeName {}
            catch {fatalError("Unexpected error for '\(name)': \(error)")}
        }
        assert(!FileManager.default.fileExists(atPath:root.appendingPathComponent("escape.aupreset").path))

        // A failed verification publishes nothing and removes the staging copy.
        do {try LibraryAssetRepair.restore(named:"Verify.aupreset",from:source,to:library){_ in throw LibraryAssetRepair.Failure.verificationFailed};fatalError("Unverified copy was published")}
        catch LibraryAssetRepair.Failure.verificationFailed {}
        assert(!FileManager.default.fileExists(atPath:library.appendingPathComponent("Verify.aupreset").path))
        let leftover=try FileManager.default.contentsOfDirectory(atPath:library.path).filter{$0.hasPrefix(".repair-")}
        assert(leftover.isEmpty,"A failed verification leaves no staging file")

        // A directory, symlink or oversized source is not a restorable sound.
        let folder=root.appendingPathComponent("Folder.aupreset")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        do {try LibraryAssetRepair.restore(named:"Folder.aupreset",from:folder,to:library){_ in};fatalError("Folder accepted as a sound")}
        catch LibraryAssetRepair.Failure.unreadableSource {}
        do {try LibraryAssetRepair.restore(named:"Missing.aupreset",from:root.appendingPathComponent("absent.aupreset"),to:library){_ in};fatalError("Missing source accepted")}
        catch {}

        // Identity: the stored name, or matching bytes - never a similar name.
        let digest=String(repeating:"a",count:64)
        let other=String(repeating:"b",count:64)
        assert(LibraryRepair.accepts(candidateName:"Pad.aupreset",digest:nil,originalDigest:nil,storedName:"Pad.aupreset"))
        assert(!LibraryRepair.accepts(candidateName:"Pad 2.aupreset",digest:nil,originalDigest:nil,storedName:"Pad.aupreset"),"A similarly named sound is not the same sound")
        assert(LibraryRepair.accepts(candidateName:"Renamed.aupreset",digest:digest,originalDigest:digest,storedName:"Pad.aupreset"),"Identical retained bytes may be renamed")
        assert(!LibraryRepair.accepts(candidateName:"Renamed.aupreset",digest:other,originalDigest:digest,storedName:"Pad.aupreset"))
        assert(!LibraryRepair.accepts(candidateName:"Renamed.aupreset",digest:digest,originalDigest:nil,storedName:"Pad.aupreset"),"No retained digest means the name must match")
        assert(!LibraryRepair.accepts(candidateName:"../Pad.aupreset",digest:nil,originalDigest:nil,storedName:"Pad.aupreset"))
        assert(!LibraryRepair.accepts(candidateName:"Pad.aupreset",digest:nil,originalDigest:nil,storedName:"../Pad.aupreset"))

        // The browser reports the detected issue as unavailable and keeps it listed.
        var broken=BrowserSound(id:"broken",name:"Pad",collection:"My Sounds",tags:SoundTags(category:"Pads",type:"Synth Pads"),external:ExternalSound(kind:.samplerPreset,name:"Pad"))
        assert(broken.playable && broken.values(.availability)==["Playable"] && broken.contentIssue == nil)
        broken=broken.checkingContent(["broken":.missingSamples])
        assert(!broken.playable && broken.values(.availability)==["Unavailable"])
        assert(broken.contentIssue == .missingSamples && broken.contentIssue?.message.contains("sample") == true)
        assert(broken.checkingContent([:]).contentIssue == nil,"A repaired sound reports no issue")
        assert(LibraryContentIssue.missingFile.message.contains("Locate"))

        print("PASS: library repair assertions")
    }
}
