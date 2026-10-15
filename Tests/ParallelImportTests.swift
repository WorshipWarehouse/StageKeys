import Foundation
import AVFoundation
import Darwin
@main struct ParallelImportTests {
    static func main()throws {
        setbuf(stdout,nil)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,audio=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
        audio.frameLength=48000;for c in 0..<2{for i in 0..<48000{audio.floatChannelData![c][i]=sin(Float(i)*2*Float.pi*220/48000)*0.15}}
        try AVAudioFile(forWriting:root.appendingPathComponent("Tone.wav"),settings:format.settings).write(from:audio)
        func branch(_ name:String,_ gain:String)->String {
            """
            <InstrumentBranchPreset><Name Value="\(name)"/><DevicePresets><AbletonDevicePreset><Device><OriginalSimpler><Player><MultiSampleMap><SampleParts><MultiSamplePart><RootKey Value="60"/><SampleStart Value="0"/><SampleEnd Value="47999"/><SampleRef><FileRef><Name Value="Tone.wav"/></FileRef></SampleRef></MultiSamplePart></SampleParts></MultiSampleMap></Player></OriginalSimpler></Device></AbletonDevicePreset><AbletonDevicePreset><Device><StereoGain><Gain><Manual Value="\(gain)"/><KeyMidi><Channel Value="16"/><NoteOrController Value="0"/></KeyMidi><MidiControllerRange><Min Value="0.001"/><Max Value="1"/></MidiControllerRange></Gain></StereoGain></Device></AbletonDevicePreset></DevicePresets></InstrumentBranchPreset>
            """
        }
        let source=root.appendingPathComponent("Parallel.adg"),preset=root.appendingPathComponent("Parallel.aupreset")
        try Data(("<Ableton><GroupDevicePreset><Device><InstrumentGroupDevice><MacroControls.0><Manual Value=\"127\"/></MacroControls.0><MacroDisplayNames.0 Value=\"Branch Blend\"/></InstrumentGroupDevice></Device><BranchPresets>"+branch("First","1")+branch("Second","0.001")+"</BranchPresets></GroupDevicePreset></Ableton>").utf8).write(to:source)
        let converted=try AbletonImport.convert(source,sampleRoot:root,to:preset)
        assert(converted.rack.branches?.count==2 && converted.rack.validate())
        assert(converted.rack.macros.count==1 && converted.rack.macros[0].bindings.count==2)
        assert(converted.rack.macros[0].bindings.map{$0.branchPath!}==[[0],[1]])
        assert(converted.rack.branches![0].rack.macros.isEmpty)
        assert(converted.rack.branches![0].sampleLayers==[0] && converted.rack.branches![1].sampleLayers==[1])
        let store=PerformanceStore();store.setlist=Setlist();store.reverb=0;store.master=0.6
        for i in store.patch.layers.indices{store.removeSound(i)}
        let sound=try store.audio.externalRack!.importPreset(preset,sampleRoot:root)
        var layer=Layer(name:"Parallel",instrument:-1,gain:0.5);layer.external=sound;layer.importedRack=converted.rack
        try store.audio.prepareOffline();store.start();store.commitLayer(0,layer)
        assert(store.audio.externalRack!.parallelBranchCount(0)==2,store.message ?? "No branches")
        func peak()throws->Float {
            store.noteOn(60,velocity:0.8);var peak:Float=0
            for _ in 0..<100 {let b=try store.audio.offlineBlock();for c in 0..<2{for i in 0..<Int(b.frameLength){let value=b.floatChannelData![c][i];assert(value.isFinite);peak=max(peak,abs(value))}}}
            store.panic();for _ in 0..<12{_ = try store.audio.offlineBlock()};return peak
        }
        let first=try peak();assert(first>0.001)
        let initial=layer.importedRack!
        layer.importedRack!.setMacro(0,value:127);store.commitLayer(0,layer);let both=try peak();assert(both>first*1.5)
        layer.importedRack=initial
        layer.importedRack!.setMacro(0,value:0)
        store.commitLayer(0,layer);let muted=try peak();print("BRANCH LEVELS",first,both,muted);assert(muted<first*0.01,"Branch gain leaked into the other path or original combined sampler still played")
        // Returning to the combined native map must reconnect the original unit.
        layer.importedRack!.branches=nil;layer.importedRack!.macros=[];store.commitLayer(0,layer);assert(store.audio.externalRack!.parallelBranchCount(0)==0);let combined=try peak();print("COMBINED",combined);assert(combined>muted*100,"Combined map did not reconnect")
        assert(store.message==nil,store.message ?? "")
        print("PASS: source parallel layer assignment, isolated effects, no doubled original sampler, finite audible graph and combined-map restoration")
    }
}
