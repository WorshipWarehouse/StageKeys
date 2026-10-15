import Foundation
@main struct AbletonPlaybackTests {
    static func main()throws {
        guard let data=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"] else{fatalError("Use an isolated converted library")}
        let store=PerformanceStore();store.setlist=Setlist();store.master=0.6;store.reverb=0
        for i in store.patch.layers.indices{store.removeSound(i)}
        try store.audio.prepareOffline();store.start()
        for volume in 1...10 {
            let collection="Sunday Free · Volume \(volume)"
            guard let entry=store.librarySounds.first(where:{$0.collection == collection}),let sound=entry.sound,let file=sound.fileName else{fatalError("Missing volume \(volume)")}
            let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:URL(fileURLWithPath:data).appendingPathComponent("Imported Sounds").appendingPathComponent(file)),options:[],format:nil) as! [String:Any]
            let layers=(state["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]],zones=layers.flatMap{$0["Zones"] as! [[String:Any]]}
            let zone=zones.first{($0["min key"] as? Int ?? 0)<=108 && ($0["max key"] as? Int ?? 127)>=21}!
            let note=max(21,max(zone["min key"] as? Int ?? 0,min(108,min(zone["max key"] as? Int ?? 127,zone["root key"] as? Int ?? 60))))
            let velocity=max(zone["min vel"] as? Int ?? 1,min(zone["max vel"] as? Int ?? 127,100))
            var testedEntry=entry
            if volume==1 {testedEntry.layer?.importedRack?.effects += [AudioEffect(),AudioEffect(),AudioEffect()]}
            store.addLibrarySound(testedEntry,index:0);assert(store.patch.layers[0].importedRack == testedEntry.layer?.importedRack);store.setGain(0,0.6);store.noteOn(note,velocity:Float(velocity)/127)
            var peak:Float=0
            for _ in 0..<200{let buffer=try store.audio.offlineBlock();for c in 0..<2{for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![c][i];assert(v.isFinite);peak=max(peak,abs(v))}}}
            assert(peak>0.00001,"Volume \(volume) is silent in the production graph")
            store.noteOff(note);store.panic()
        }
        var timeline=ProcessInfo.processInfo.systemUptime
        for name in ["Under Over Arp","Two Three Arp","Noise Pluck Arp","Candy Arp"] {
            guard let entry=store.librarySounds.first(where:{$0.name.contains(name)}),entry.layer?.midiProgram?.kind == .arpeggiator else{continue}
            store.addLibrarySound(entry,index:0);store.setGain(0,0.5);store.noteOn(60,velocity:0.8);store.noteOn(64,velocity:0.8);store.noteOn(67,velocity:0.8)
            var peak:Float=0
            for _ in 0..<500 {
                timeline=max(timeline,ProcessInfo.processInfo.systemUptime)+512.0/48000
                store.midiFX.advance(to:timeline)
                store.audio.externalRack?.advanceBranches(to:timeline)
                let buffer=try store.audio.offlineBlock()
                for channel in 0..<2 {for frame in 0..<Int(buffer.frameLength) {let value=buffer.floatChannelData![channel][frame];assert(value.isFinite);peak=max(peak,abs(value))}}
            }
            assert(peak>0.00001 && peak<1,"Imported arp/delay production graph failed: \(name), \(peak)")
            store.panic();print("ARP/DELAY GRAPH",name,"peak",peak)
        }
        for entry in store.librarySounds.filter({!($0.layer?.importedRack?.branches?.isEmpty ?? true)}) {
            store.addLibrarySound(entry,index:0);store.setGain(0,0.5)
            assert(store.audio.externalRack!.parallelBranchCount(0)>0,entry.name)
            store.noteOn(60,velocity:0.8);store.noteOn(64,velocity:0.8);store.noteOn(67,velocity:0.8)
            var peak:Float=0
            for _ in 0..<250 {
                timeline=max(timeline,ProcessInfo.processInfo.systemUptime)+512.0/48000
                store.midiFX.advance(to:timeline);store.audio.externalRack?.advanceBranches(to:timeline)
                let buffer=try store.audio.offlineBlock()
                for c in 0..<2 {for f in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![c][f];assert(v.isFinite);peak=max(peak,abs(v))}}
            }
            assert(peak>0.000001 && peak<1,"Parallel production graph: \(entry.name), \(peak)")
            store.panic();print("PARALLEL GRAPH",entry.name,"peak",peak)
        }
        assert(store.message==nil,store.message ?? "")
        print("PASS: all ten Ableton volumes → library selection → production channel/effect graph → finite audible audio, note-off and panic")
    }
}
