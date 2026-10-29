import Foundation

@main struct MetadataRecoveryTests {
    @MainActor static func main()throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let ratings=root.appendingPathComponent("sound-ratings.json"),presets=root.appendingPathComponent("effect-presets.json")
        let originalRatings=["owned":4],changedRatings=["owned":5]
        let effect=AudioEffect.factoryDefault(kind:13)
        let originalPreset=EffectPreset(name:"Personal room",effect:effect)
        var changedPreset=originalPreset;changedPreset.name="Edited room"
        try SoundRatingArchive.save(originalRatings,to:ratings);try SoundRatingArchive.save(changedRatings,to:ratings)
        try EffectPresetArchive.save([originalPreset],to:presets);try EffectPresetArchive.save([changedPreset],to:presets)
        let ratingsBackup=try Data(contentsOf:RecoverableSessionFile.previous(ratings))
        let presetsBackup=try Data(contentsOf:RecoverableSessionFile.previous(presets))
        let damaged=Data("interrupted metadata".utf8)
        try damaged.write(to:ratings);try damaged.write(to:presets)
        let store=PerformanceStore()
        assert(store.ratingsRecoveryRequired && store.presetsRecoveryRequired)
        store.rateSound("other",3);store.saveEffectPreset(effect,name:"New room");store.save()
        assert(store.soundRatings.isEmpty && store.effectPresets.isEmpty)
        assert((try! Data(contentsOf:ratings))==damaged && (try! Data(contentsOf:presets))==damaged)
        assert((try! Data(contentsOf:RecoverableSessionFile.previous(ratings)))==ratingsBackup)
        assert((try! Data(contentsOf:RecoverableSessionFile.previous(presets)))==presetsBackup)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let current=try encoder.encode(store.setlist)
        store.recoverPreviousRatings();store.recoverPreviousPresets()
        assert(!store.ratingsRecoveryRequired && !store.presetsRecoveryRequired)
        assert(store.soundRatings==originalRatings && store.effectPresets==[originalPreset])
        let unchanged=try encoder.encode(store.setlist);assert(unchanged==current,"Recovery changed active patch/effect settings")
        let restarted=PerformanceStore()
        assert(!restarted.ratingsRecoveryRequired && !restarted.presetsRecoveryRequired)
        assert(restarted.soundRatings==originalRatings && restarted.effectPresets==[originalPreset])
        let archives=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.contains(".damaged-")}
        assert(archives.count==2 && archives.allSatisfy{(try? Data(contentsOf:$0))==damaged})

        func unsafeCases(_ name:String,backup:Data,read:(URL)throws->Void,save:(URL)throws->Void,recover:(URL)throws->Void)throws {
            let dir=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let large=dir.appendingPathComponent("large.json")
            FileManager.default.createFile(atPath:large.path,contents:nil)
            let handle=try FileHandle(forWritingTo:large);try handle.truncate(atOffset:4_000_001);try handle.close()
            try backup.write(to:RecoverableSessionFile.previous(large))
            let hash=try AssetDigest.sha256(large)
            do{try read(large);fatalError("Oversized metadata accepted")}catch{}
            do{try save(large);fatalError("Oversized metadata overwritten")}catch{}
            try recover(large);try read(large)
            let retained=try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.contains(".damaged-")}
            let hashes=try retained.map{try AssetDigest.sha256($0)};assert(hashes==[hash])
            for (file,target) in [("linked.json",large),("dangling.json",dir.appendingPathComponent("missing.json"))] {
                let link=dir.appendingPathComponent(file)
                try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
                try backup.write(to:RecoverableSessionFile.previous(link))
                do{try read(link);fatalError("Linked metadata read")}catch{}
                do{try save(link);fatalError("Linked metadata written")}catch{}
                do{try recover(link);fatalError("Linked metadata restored")}catch{}
                assert((try! link.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true)
            }
            let invalid=dir.appendingPathComponent("invalid.json")
            try damaged.write(to:invalid)
            do{try recover(invalid);fatalError("Missing backup accepted")}catch{}
            try damaged.write(to:RecoverableSessionFile.previous(invalid))
            do{try recover(invalid);fatalError("Invalid backup accepted")}catch{}
            assert((try! Data(contentsOf:invalid))==damaged)
        }
        try unsafeCases("ratings",backup:ratingsBackup,read:{_ = try SoundRatingArchive.read($0)},save:{try SoundRatingArchive.save(originalRatings,to:$0)},recover:{_ = try SoundRatingArchive.recover($0)})
        try unsafeCases("presets",backup:presetsBackup,read:{_ = try EffectPresetArchive.read($0)},save:{try EffectPresetArchive.save([originalPreset],to:$0)},recover:{_ = try EffectPresetArchive.recover($0)})
        print("PASS: ratings/preset failed-load flags, blocked UI saves, explicit recovery/restart, unchanged active effects, bounded reads, hashes, unsafe links and invalid/missing backups")
    }
}
