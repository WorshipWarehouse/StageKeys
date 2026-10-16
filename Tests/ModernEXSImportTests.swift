import Foundation
import AVFoundation
@main struct ModernEXSImportTests {
    static func main()throws {
        guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_FIXTURE"],let root=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_ROOT"] else{print("SKIP: provide private EXS fixture and selected sample root");return}
        let scratch=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:scratch)}
        let source=URL(fileURLWithPath:path),original=try AbletonArchive.sha256(source)
        let rack=try ExternalInstrumentRack(engine:AVAudioEngine(),libraryURL:scratch.appendingPathComponent("Imported Sounds"))
        let sound=try rack.importEXS(source,sampleRoot:URL(fileURLWithPath:root))
        assert(sound.nativeSampler?.groups.count==20 && sound.nativeSampler?.rack.validate()==true && sound.nativeSampler?.rack.branches?.count==2)
        let map=try StageKeysSampler.map(sound,library:rack.libraryURL)
        assert(map.zones.count==224 && map.layerCount==20 && map.sampleCount==1)
        let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:rack.libraryURL.appendingPathComponent(sound.fileName!)),options:[],format:nil) as! [String:Any]
        let refs=state["file-references"] as! [String:String]
        let sourceAudio=URL(fileURLWithPath:root).appendingPathComponent("EXS Factory Samples/01 Acoustic Pianos/Steinway Piano_consolidated.caf")
        let copiedAudio=URL(fileURLWithPath:refs.values.first!)
        let sourceHash=try AbletonArchive.sha256(sourceAudio),copyHash=try AbletonArchive.sha256(copiedAudio)
        assert(sourceHash==copyHash,"Import must preserve the complete original CAF byte-for-byte")
        let after=try AbletonArchive.sha256(source);assert(after==original)
        let retained=try StageKeysSampler.retainOriginal(source,library:scratch)
        assert(retained.sha256==original)
        // Reconstruct a v0.27 preset to exercise an actual installed-library
        // upgrade, including its untouched-envelope guard and exact map retention.
        var legacy=sound,program=sound.nativeSampler!
        program.conversionVersion=nil;program.amplitudeEnvelope=nil;legacy.nativeSampler=program
        var oldState=state,oldInstrument=state["Instrument"] as! [String:Any],oldLayers=(state["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
        let parts=try EXSNative.chunks(Data(contentsOf:source))
        for rule in program.groups {
            let group=parts.first{$0.kind==2 && $0.name==rule.name}!
            EXSNative.applyEnvelope(nil,group:group.body,to:&oldLayers[rule.layer])
        }
        oldInstrument["Layers"]=oldLayers;oldState["Instrument"]=oldInstrument;oldState["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        let file=rack.libraryURL.appendingPathComponent(sound.fileName!)
        let legacyBytes=try PropertyListSerialization.data(fromPropertyList:oldState,format:.xml,options:0);try legacyBytes.write(to:file)
        let updated=try StageKeysSampler.updateEnvelope(legacy,original:retained,library:scratch)
        assert(updated.nativeSampler?.amplitudeEnvelope?.decay==10 && updated.nativeSampler?.conversionVersion==2)
        let upgraded=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as! [String:Any]
        let newLayers=(upgraded["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
        for index in oldLayers.indices {
            var old=oldLayers[index],new=newLayers[index];old.removeValue(forKey:"Envelopes");new.removeValue(forKey:"Envelopes")
            assert(NSDictionary(dictionary:old)==NSDictionary(dictionary:new),"Envelope upgrade must not change zones, gain or native routing")
        }
        assert(NSDictionary(dictionary:upgraded["file-references"] as! [String:Any])==NSDictionary(dictionary:refs))
        let backup=scratch.appendingPathComponent("Sampler Backups/"+MainStagePatch.digest(legacyBytes)+".aupreset")
        let backupBytes=try Data(contentsOf:backup);assert(backupBytes==legacyBytes)
        // A hand-edited release must stay intact.
        var edited=oldState,editInstrument=oldInstrument,editLayers=oldLayers
        var envelopes=editLayers[0]["Envelopes"] as! [[String:Any]],stages=envelopes[0]["Stages"] as! [[String:Any]]
        stages[5]["time"]=2.75;envelopes[0]["Stages"]=stages;editLayers[0]["Envelopes"]=envelopes
        editInstrument["Layers"]=editLayers;edited["Instrument"]=editInstrument
        let editedBytes=try PropertyListSerialization.data(fromPropertyList:edited,format:.xml,options:0);try editedBytes.write(to:file)
        do{_ = try StageKeysSampler.updateEnvelope(legacy,original:retained,library:scratch);assertionFailure("Edited envelope overwritten")}catch{}
        let preservedEdit=try Data(contentsOf:file);assert(preservedEdit==editedBytes)
        // Exercise Store migration with user-edited names/levels/rack settings.
        try legacyBytes.write(to:file)
        setenv("STAGEKEYS_DATA_DIR",scratch.path,1)
        let store=PerformanceStore()
        var user=Layer(name:"My Piano",instrument:-1,gain:0.231)
        var named=legacy;named.name="My Instrument Label";named.bankMSB=13
        user.external=named;user.pan = -0.3;user.blockSustain=true
        var custom=AudioEffect();custom.kind=9;custom.parameters=[-7]
        var userRack=program.rack;userRack.effects=[custom];user.importedRack=userRack
        let entry=LibrarySound(id:"legacy-test",name:"My Library Label",collection:"MainStage Samplers",sound:named,layer:user,originalInstrument:retained)
        store.librarySounds=[entry]
        store.setlist.patches[0].layers[0]=user
        store.updateSamplerEnvelopes()
        let actual=store.setlist.patches[0].layers[0]
        assert(actual.name==user.name && actual.id==user.id && actual.gain==user.gain && actual.pan==user.pan && actual.blockSustain==user.blockSustain && actual.importedRack==user.importedRack)
        assert(actual.external?.name==named.name && actual.external?.bankMSB==13 && actual.external?.nativeSampler?.conversionVersion==2)
        assert(store.librarySounds[0].name==entry.name && store.librarySounds[0].sound?.name==named.name && store.librarySounds[0].layer?.importedRack==userRack)
        assert(store.libraryImportProgress?.contains("Updated 1")==true,store.libraryImportProgress ?? "No upgrade status")
        print("PASS: existing native EXS envelope upgrade, original preset backup, exact zone/routing/sample retention and edited-envelope protection")
        print("PASS: real EXS import API fallback, 224 zones/20 MIDI-selected groups, identical original CAF SHA-256 and unchanged EXS source")
    }
}
