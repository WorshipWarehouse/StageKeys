import Foundation
@main struct TonicPadTests {
    static func main()throws {
        let store=PerformanceStore();assert(store.librarySounds.isEmpty && store.tonicSound==nil)
        store.toggleTonic(7);assert(store.tonic==nil)
        store.setlist=TestFixtures.setlist()
        try store.audio.prepareOffline();store.start();assert(store.started,store.message ?? "Audio failed")
        for i in store.patch.layers.indices {store.setGain(i,0)}
        store.master=0.3;store.reverb=0;store.tonicGain=0.3
        store.selectTonicRoot(7);assert(store.tonic==nil && store.tonicLastRoot==7,"Key selection must not engage bypassed pad");store.toggleTonic(7);assert(store.tonic==nil && store.message != nil,"No pad may play without a user sound")
        store.message=nil;let fixture=TestFixtures.padSound();assert(store.tonicSoundEligibility(fixture)==nil,store.tonicSoundEligibility(fixture) ?? "");store.setTonicInstrument(fixture);store.toggleTonic(7);assert(store.tonic==7,store.message ?? "Pad did not start")
        store.selectTonicRoot(7);assert(store.tonic==7,"Repeated root selection must not stop the pad")
        var energy:Double=0
        for _ in 0..<100 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![0][i];assert(v.isFinite);energy+=Double(v*v)}}
        assert(energy>0.001,"Explicit synthetic pad must be audible")
        store.tonicShimmer=0.7;assert(store.tonic==7,"Changing shimmer must not stop/retrigger tonic selection")
        let invalidTonic=ExternalSound(kind:.audioUnit,name:"Unsupported AU",component:ExternalAUIdentity(type:0x61756d75,subtype:1,manufacturer:1,name:"Unsupported AU"))
        assert(store.tonicSoundEligibility(invalidTonic) != nil,"Audio Units and unsupported maps must be rejected for Tonic Pad selection")
        let missingPreset=ExternalSound(kind:.samplerPreset,name:"Missing preset",fileName:"missing.auk")
        assert(store.tonicSoundEligibility(missingPreset) != nil,"A missing library instrument must be rejected with an eligibility reason")
        for _ in 0..<50 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){assert(buffer.floatChannelData![0][i].isFinite)}}
        store.toggleTonic(7);assert(store.tonic==nil && store.tonicLastRoot==7)
        store.toggleTonic(store.tonicLastRoot);assert(store.tonic==7)
        store.toggleTonicPatchLock();assert(store.tonicLocked)
        let saved=store.patch.tonicState!
        store.tonicBrightness=0.2;store.selectTonicRoot(2)
        let first=store.selected;let next=(first+1)%store.setlist.patches.count
        store.choose(next);assert(store.tonic==2,"Unlocked patch must let the pad continue")
        store.choose(first);assert(store.tonic==7 && store.tonicBrightness==saved.brightness,"Patch Lock must recall its saved state")
        let decodedPatch=try JSONDecoder().decode(Patch.self,from:JSONEncoder().encode(store.patch));assert(decodedPatch.tonicState==saved)
        store.toggleTonicPatchLock();assert(!store.tonicLocked)
        store.toggleTonic(7);store.selectTonicRoot(5);store.toggleTonicPatchLock()
        store.choose(next);store.toggleTonic(2);store.choose(first)
        assert(store.tonic==nil && store.tonicLastRoot==5,"Patch recall must restore selected key and bypass independently")
        store.toggleTonicPatchLock();store.toggleTonic(7)
        let settings=SessionSettings(tonicTimbre:11,tonicLastRoot:7,tonicLocked:true)
        assert(settings.validate());let restored=try JSONDecoder().decode(SessionSettings.self,from:JSONEncoder().encode(settings));assert(restored.tonicTimbre==11 && restored.tonicLastRoot==7 && restored.tonicLocked==true)
        if let source=ProcessInfo.processInfo.environment["STAGEKEYS_TONIC_FIXTURE"],let samples=ProcessInfo.processInfo.environment["STAGEKEYS_TONIC_ROOT"] {
            store.importTonicInstrument(URL(fileURLWithPath:source),samples:URL(fileURLWithPath:samples))
            assert(store.message==nil,store.message ?? "")
            assert(store.tonicVelocitySelector && store.tonicNames.count==12 && store.tonicSound?.fileName != nil,store.message ?? "Native tonic failed")
            store.tonicShimmer=0
            for timbre in 0..<12 {
                store.tonicTimbre=timbre
                var energy:Double=0
                for _ in 0..<100 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![0][i];assert(v.isFinite);energy+=Double(v*v)}}
                assert(energy>0.00000001,"Native tonic timbre \(timbre+1) must select its original zone")
            }
            let originalSound=store.tonicSound,originalTimbre=store.tonicTimbre
            store.toggleTonicPatchLock();assert(store.patch.tonicState?.sound==originalSound && store.patch.tonicState?.velocitySelector==true,"Patch lock must capture selected sampler and selector mode")
            store.choose(next);for i in store.patch.layers.indices {store.setGain(i,0)}
            var continued:Double=0
            for _ in 0..<100 {let buffer=try store.audio.offlineBlock();for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![0][i];continued+=Double(v*v)}}
            assert(continued>0.00000001,"Imported tonic must still produce audio after selecting an unlocked patch")
            store.choose(first);assert(store.tonicSound==originalSound && store.tonicVelocitySelector && store.tonicTimbre==originalTimbre,"Patch lock recall must restore the selected sampler mode")
            print("PASS: all twelve original tonic velocity-selected timbres render through production Store routing")
        }
        store.panic();assert(store.tonic==nil)
        print("PASS: no empty-pad sound, explicit synthetic tonic audio, same-key selection, power key memory, stable shimmer and settings persistence")
    }
}
