import Foundation
@main struct OutputHeadroomTests {
    static func main()throws {
        guard ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"] != nil else{fatalError("Use an isolated converted library")}
        let store=PerformanceStore();store.setlist=Setlist();store.master=0.6;store.reverb=0
        for i in store.patch.layers.indices{store.removeSound(i)}
        try store.audio.prepareOffline();store.start()
        for name in ["Airy EP", "Synthetic Piano"] {
            let entry=store.librarySounds.first{$0.name.contains(name)}!
            for channel in 0..<8 { store.addLibrarySound(entry,index:channel);store.setGain(channel,1) };store.master=1;store.setSustain(true)
            for note in [48,52,55,59,60,64,67,71,72,76] {store.noteOn(note,velocity:1)}
            var peak:Float=0
            for block in 0..<600{if block % 60 == 0 { for note in [48,52,55,59,60,64,67,71,72,76] { store.noteOff(note);store.noteOn(note,velocity:1) } };let b=try store.audio.offlineBlock();for c in 0..<2{for i in 0..<Int(b.frameLength){let value=b.floatChannelData![c][i];assert(value.isFinite);peak=max(peak,abs(value))}}}
            assert(peak > 0.01 && peak < 0.95,"Output overload: \(peak)");print("SUSTAINED EIGHT-LAYER CHORD",name,"peak",peak)
            store.panic()
        }
        assert(store.message==nil,store.message ?? "")
        print("PASS: repeated sustained chords across eight sampler channels remain finite and below full scale")
    }
}
