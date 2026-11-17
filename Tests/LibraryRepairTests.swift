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
            assert(temporary.deletingLastPathComponent().resolvingSymlinksInPath().path==library.resolvingSymlinksInPath().path,"The staged copy stays in the managed folder")
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
        assert(!LibraryRepair.accepts(candidateName:"Pad.aupreset",digest:nil,originalDigest:nil,storedName:"Pad.aupreset"))
        assert(!LibraryRepair.accepts(candidateName:"Pad.aupreset",digest:other,originalDigest:digest,storedName:"Pad.aupreset"),"Same name with different bytes is not identity")
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

        // Exercise the actual Store copy/publication path with a generated WAV.
        _ = TestFixtures.sound()
        let store=PerformanceStore()
        let wave=root.appendingPathComponent("Generated Fixture 0.wav")
        let imported=store.importLibrarySound(wave)!
        let entry=store.librarySounds.first{$0.sound == imported}!
        assert(entry.managedFileSHA256 != nil)
        let managed=store.audio.externalRack!.libraryURL.appendingPathComponent(imported.fileName!)
        let expected=try AssetDigest.sha256(managed)
        let moved=root.appendingPathComponent("Renamed identical.wav")
        try FileManager.default.moveItem(at:managed,to:moved)
        store.save()
        let session=try Data(contentsOf:root.appendingPathComponent("setlist.json"))
        store.refreshLibraryContent();assert(store.libraryContentIssues[entry.id] == .missingFile)
        // A wrong file with the exact managed name is refused without publication.
        let wrong=root.appendingPathComponent(imported.fileName!)
        try Data("different bytes".utf8).write(to:wrong)
        store.relinkLibrarySound(entry.id,from:wrong)
        assert(!FileManager.default.fileExists(atPath:managed.path))
        store.relinkLibrarySound(entry.id,from:moved)
        assert(store.libraryContentIssues[entry.id] == nil)
        assert((try! AssetDigest.sha256(managed)) == expected && (try! AssetDigest.sha256(moved)) == expected)
        assert((try! Data(contentsOf:root.appendingPathComponent("setlist.json"))) == session)
        let reloaded=try SoundLibrary(url:root.appendingPathComponent("sound-library.json")).read()
        assert(reloaded.first{$0.id == entry.id}?.managedFileSHA256 == expected)
        // A sampler preset whose managed sample folder was moved can be repaired by
        // pointing at the folder that now holds the samples: the retained original
        // is re-resolved, the samples are copied back into managed storage and the
        // catalog is republished only when the repaired preset is complete.
        func fourCC(_ text:String)->NSNumber {
            NSNumber(value:text.unicodeScalars.reduce(UInt32(0)) {($0 << 8) | UInt32($1.value)})
        }
        let movedSamples=root.appendingPathComponent("Moved Samples")
        try FileManager.default.createDirectory(at:movedSamples,withIntermediateDirectories:true)
        try Data("RIFF moved sample bytes".utf8).write(to:movedSamples.appendingPathComponent("Missing Pad.wav"))
        let presetSource=root.appendingPathComponent("Missing Pad.aupreset")
        let presetState:[String:Any]=["type":fourCC("aumu"),"subtype":fourCC("samp"),"manufacturer":fourCC("appl"),
                                      "file-references":["sample-1":"/previous/library/Missing Pad.wav"]]
        try PropertyListSerialization.data(fromPropertyList:presetState,format:.xml,options:0).write(to:presetSource)
        let samplerSound=store.importLibrarySound(presetSource,sampleRoot:movedSamples)!
        let samplerEntry=store.librarySounds.first{$0.sound == samplerSound}!
        assert(samplerEntry.originalInstrument != nil,"the unmodified preset is retained for repair")
        let rack=store.audio.externalRack!
        let managedPreset=rack.libraryURL.appendingPathComponent(samplerSound.fileName!)
        let managedSamples=URL(fileURLWithPath:managedPreset.deletingPathExtension().path+"-samples")
        assert(FileManager.default.fileExists(atPath:managedSamples.path),"the import copies the samples into managed storage")
        try FileManager.default.removeItem(at:managedSamples)
        store.refreshLibraryContent()
        assert(store.libraryContentIssues[samplerEntry.id] == .missingSamples,"a lost sample folder is reported as missing samples")
        assert(store.libraryContentIssues[samplerEntry.id]?.repairsWithFolder == true,"missing samples need a folder, not a file")
        // A wrong folder refuses the repair and leaves every published byte alone.
        let emptyFolder=root.appendingPathComponent("Empty Folder")
        try FileManager.default.createDirectory(at:emptyFolder,withIntermediateDirectories:true)
        let catalogBefore=try AssetDigest.sha256(root.appendingPathComponent("sound-library.json"))
        store.relinkLibrarySamples(samplerEntry.id,from:emptyFolder)
        assert(store.libraryContentIssues[samplerEntry.id] == .missingSamples,"a refused repair must not claim success")
        assert(store.message?.contains("Missing sample") == true,"the refusal names the missing sample: \(store.message ?? "")")
        assert((try! AssetDigest.sha256(root.appendingPathComponent("sound-library.json"))) == catalogBefore,"a refused repair must not rewrite the catalog")
        assert(!FileManager.default.fileExists(atPath:managedSamples.path),"a refused repair publishes no sample copy")
        assert((try! Data(contentsOf:root.appendingPathComponent("setlist.json"))) == session)
        // The folder that holds the samples repairs the entry to playable.
        store.relinkLibrarySamples(samplerEntry.id,from:movedSamples)
        assert(store.libraryContentIssues[samplerEntry.id] == nil,store.message ?? "")
        let repairedEntry=store.librarySounds.first{$0.id == samplerEntry.id}!
        assert(repairedEntry.sound?.fileName != samplerSound.fileName,"repair publishes a new managed preset")
        assert(repairedEntry.sound?.kind == .samplerPreset && repairedEntry.name == samplerEntry.name)
        assert(repairedEntry.tags == samplerEntry.tags,"repair keeps the entry's personal metadata")
        assert(repairedEntry.originalInstrument == samplerEntry.originalInstrument,"the retained original is unchanged")
        assert(repairedEntry.sound?.name == samplerSound.name,"repair keeps the sound name the user sees, not a content digest")
        let publishedPreset=rack.libraryURL.appendingPathComponent(repairedEntry.sound!.fileName!)
        assert(repairedEntry.managedFileSHA256 == (try! AssetDigest.sha256(publishedPreset)),"the stored digest describes the repaired preset")
        assert(repairedEntry.managedFileSHA256 != samplerEntry.managedFileSHA256,"repair changes the preset bytes, so the digest changes")
        assert(FileManager.default.fileExists(atPath:rack.libraryURL.appendingPathComponent(repairedEntry.sound!.fileName!).path))
        assert(FileManager.default.fileExists(atPath:managedPreset.path),"the previous managed preset is kept for saved patches")
        assert((try! Data(contentsOf:root.appendingPathComponent("setlist.json"))) == session)
        let repairedCatalog=try SoundLibrary(url:root.appendingPathComponent("sound-library.json")).read()
        assert(repairedCatalog.first{$0.id == samplerEntry.id}?.sound?.fileName == repairedEntry.sound?.fileName)
        assert(store.message?.contains("Reconnected") == true,store.message ?? "")
        print("PASS: library repair assertions, remove-from-My-Sounds and missing-samples repair")
    }
}
