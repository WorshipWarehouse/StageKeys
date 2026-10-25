import Foundation
import AVFoundation
@main struct SamplerStartupTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source=root.appendingPathComponent("Original.wav")
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;pcm.frameLength=48000
        for frame in 0..<48000 {pcm.floatChannelData![0][frame]=0.2*sin(Float(frame)*2 * .pi*261.626/48000)}
        do {let file=try AVAudioFile(forWriting:source,settings:format.settings);try file.write(from:pcm)}
        let original=try Data(contentsOf:source)
        let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
        let rack=audio.externalRack!
        let sound=try rack.importSound(source)
        var layer=Layer(name:"Startup sampler",instrument:-1,gain:0.5);layer.external=sound
        audio.configure(0,layer);audio.gain(0,0.5,seconds:0);audio.master(1);audio.space(0)
        let loaded=rack.samplerRestorationCount
        assert(loaded>0)
        for index in 1..<16 {
            try rack.remove(index)
            audio.configure(index,Layer.empty())
        }
        assert(rack.samplerRestorationCount==loaded,"Empty slots reloaded unrelated sample instruments")
        assert(audio.running,"Empty slots stopped the engine")
        audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.8)
        var peak:Float=0
        for _ in 0..<20 {let buffer=try audio.offlineBlock();for i in 0..<Int(buffer.frameLength){peak=max(peak,abs(buffer.floatChannelData![0][i]))}}
        assert(peak>0.001,"Resident sampler stopped playing after empty-slot configuration")
        assert((try! Data(contentsOf:source))==original)
        let beforeBatch = rack.samplerRestorationCount
        try audio.withGraphChanges {
            audio.configure(1, layer); audio.configure(2, layer)
        }
        assert(rack.samplerRestorationCount - beforeBatch == 3, "Patch graph edits must restore each attached sampler just once")
        enum ProbeFailure: Error { case expected }
        do { try audio.withGraphChanges { try rack.remove(2); throw ProbeFailure.expected } } catch ProbeFailure.expected {}
        assert(audio.running && rack.unit(channel: 0) != nil && rack.unit(channel: 1) != nil)
        try audio.withGraphChanges {} // No-op batch must not restore or stop anything.
        try rack.remove(0)
        assert(rack.unit(channel:0)==nil)
        print("PASS: configuring/removing 15 empty slots adds zero sampler restorations, keeps audio running and preserves loaded sound/source bytes")
    }
}
