import Foundation

@main struct AllSoundSlotsTests {
    static func main() throws {
        let store=PerformanceStore();try store.audio.prepareOffline();store.start();defer{store.audio.stop()}
        store.reverb=0;store.master=0.2
        for i in 0..<15 {store.removeSound(i)}
        for index in 0..<15 {
            store.addSound(index,index%3);store.setRange(index,low:48,high:84)
            var layer=store.patch.layers[index];layer.pan=Float(index-7)/10
            layer.effects[0]=AudioEffect.factoryDefault(kind:9);layer.effects[0].parameters=[Float(-index)]
            store.commitLayer(index,layer)
            for other in 0..<15{store.setGain(other,other==index ? 0.3:0)}
            store.panic();store.noteOn(60,velocity:0.8)
            var peak:Float=0
            for _ in 0..<60 {
                let b=try store.audio.offlineBlock()
                for c in 0..<Int(b.format.channelCount){for n in 0..<Int(b.frameLength){let x=b.floatChannelData![c][n];assert(x.isFinite);peak=max(peak,abs(x))}}
            }
            assert(peak>0.00001,"Sound slot \(index+1) did not render")
            store.noteOff(60);store.panic()
        }
        store.captureSnapshot(0)
        let before=store.patch.layers.map(\.id),settings=store.patch.layers.map(\.effects)
        store.reorderLayer(14,0)
        assert(store.patch.layers[0].id==before[14] && store.patch.layers[0].effects==settings[14])
        assert(store.patch.snapshots[0].sounds![0].effects==settings[14])
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let bytes=try encoder.encode(store.setlist)
        for index in [-1,15,100] {store.setGain(index,.nan);store.removeSound(index);store.addSound(index,0);store.mute(index);store.setRange(index,low:0,high:127)}
        store.setGain(0,.infinity);store.setRange(0,low:90,high:10);store.setEffect(0,100,AudioEffect())
        assert(try! encoder.encode(store.setlist)==bytes)
        try store.setlist.validate()
        print("PASS: all 15 slots render independently; reorder retains effect/snapshot identity; invalid/stale edits leave session unchanged")
    }
}
