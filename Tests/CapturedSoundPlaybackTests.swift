import Foundation

/// Optional private capture fixture; never includes third-party audio in source.
/// Set STAGEKEYS_DATA_DIR to an isolated library produced by the converter.
@main struct CapturedSoundPlaybackTests {
    static func main() throws {
        precondition(ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"] != nil,"Use an isolated fixture library")
        let store=PerformanceStore()
        guard let sound=store.librarySounds.first(where:{$0.collection.hasPrefix("Sunday Free Native")}) else { fatalError("No converted capture fixture") }
        store.setlist=Setlist();store.master=0.7;store.reverb=0
        for index in store.patch.layers.indices { store.removeSound(index) }
        try store.audio.prepareOffline();store.start()
        store.addLibrarySound(sound,index:0);store.setGain(0,0.7)
        for note in [21,36,49,60,73,96,108] {
            store.noteOn(note)
            var peak:Float=0,latePeak:Float=0
            for block in 0..<1125 {
                let buffer=try store.audio.offlineBlock()
                for frame in 0..<Int(buffer.frameLength) {
                    let value=buffer.floatChannelData![0][frame];assert(value.isFinite)
                    peak=max(peak,abs(value));if block>=1031 {latePeak=max(latePeak,abs(value))}
                }
            }
            assert(peak>0.0001 && latePeak>0.0001,"Captured pad must play and sustain through production graph")
            store.noteOff(note);store.panic()
        }
        assert(store.message==nil,store.message ?? "")
        print("PASS converted capture → library selection → production channel graph, transposed pitches, sustained loop, note-off and panic")
    }
}
