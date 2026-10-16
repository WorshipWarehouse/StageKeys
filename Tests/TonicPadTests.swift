import Foundation
@main struct TonicPadTests {
    static func main()throws {
        let store=PerformanceStore();assert(store.librarySounds.isEmpty && store.tonicSound==nil)
        try store.audio.prepareOffline();store.start();assert(store.started,store.message ?? "Audio failed")
        for i in store.patch.layers.indices {store.setGain(i,0)}
        store.master=0.3;store.reverb=0;store.tonicGain=0.3
        store.selectTonicRoot(7);assert(store.tonic==7 && store.tonicLastRoot==7)
        store.selectTonicRoot(7);assert(store.tonic==7,"Repeated root selection must not stop the pad")
        var energy:Double=0
        for _ in 0..<100 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![0][i];assert(v.isFinite);energy+=Double(v*v)}}
        assert(energy>0.001,"Library-free tonic must be audible")
        store.tonicShimmer=0.7;assert(store.tonic==7,"Changing shimmer must not stop/retrigger tonic selection")
        for _ in 0..<50 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){assert(buffer.floatChannelData![0][i].isFinite)}}
        store.toggleTonic(7);assert(store.tonic==nil && store.tonicLastRoot==7)
        store.toggleTonic(store.tonicLastRoot);assert(store.tonic==7)
        store.tonicLocked=true;store.save()
        let settings=SessionSettings(tonicTimbre:11,tonicLastRoot:7,tonicLocked:true)
        assert(settings.validate());let restored=try JSONDecoder().decode(SessionSettings.self,from:JSONEncoder().encode(settings));assert(restored.tonicTimbre==11 && restored.tonicLastRoot==7 && restored.tonicLocked==true)
        if let source=ProcessInfo.processInfo.environment["STAGEKEYS_TONIC_FIXTURE"],let samples=ProcessInfo.processInfo.environment["STAGEKEYS_TONIC_ROOT"] {
            store.importTonicInstrument(URL(fileURLWithPath:source),samples:URL(fileURLWithPath:samples))
            assert(store.message==nil,store.message ?? "")
            assert(store.tonicVelocitySelector && store.tonicNames.count==12 && store.librarySounds.last?.collection=="Tonic Pads",store.message ?? "Native tonic failed")
            store.tonicShimmer=0
            for timbre in 0..<12 {
                store.tonicTimbre=timbre
                var energy:Double=0
                for _ in 0..<100 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![0][i];assert(v.isFinite);energy+=Double(v*v)}}
                assert(energy>0.00000001,"Native tonic timbre \(timbre+1) must select its original zone")
            }
            print("PASS: all twelve original tonic velocity-selected timbres render through production Store routing")
        }
        store.panic();assert(store.tonic==nil)
        print("PASS: library-free tonic audio, same-key selection, power key memory, stable shimmer and settings persistence")
    }
}
