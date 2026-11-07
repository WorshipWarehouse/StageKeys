import Foundation
import AVFoundation

@main struct ImportedSignalOrderTests {
    static func main() throws {
        let store=PerformanceStore()
        store.setlist=TestFixtures.setlist()
        try store.audio.prepareOffline()
        store.start()
        defer { store.stopAudio() }
        guard let order=store.audio.externalRack!.debugSignalOrder(channel:0) else {
            fatalError("Could not trace imported instrument connections; graph generation \(store.audio.externalRack!.graphGeneration)")
        }
        assert(order == ["Instrument","Source gain","Compressor","Mod Filter","EQ",
                         "Audio slots","Stereo pan","Performance fader","Main mixer"],
               "Imported instruments must use source gain → compressor → filter → EQ → effects → pan → fader: \(order)")
        print("PASS: imported instrument graph enforces source gain, compressor, Mod Filter, EQ, effects, pan and fader order")
    }
}
