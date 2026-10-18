import Foundation
import AVFoundation

/// Optional private-fixture regression. Offline-only renders did not reproduce
/// the converted piano's live, buffer-boundary attack impulses.
@main struct RealtimePianoTests {
    static func main() throws {
        guard let fixture=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"] else {print("SKIP: private piano fixture unset");return}
        let file=URL(fileURLWithPath:fixture),bytes=try Data(contentsOf:file)
        let state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
        let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data)
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let destination=root.appendingPathComponent("Imported Sounds",isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        try bytes.write(to:destination.appendingPathComponent(file.lastPathComponent))
        var layer=Layer(name:"Realtime piano fixture",instrument:-1,gain:1)
        layer.external=ExternalSound(kind:.samplerPreset,name:layer.name,fileName:file.lastPathComponent,nativeSampler:program)
        assert(layer.samplerAttackMinimum==0,"Native playback must not add the former 40 ms onset smoothing")
        func maximumStep(_ samples:[Float])->Float {
            assert(samples.allSatisfy(\.isFinite))
            return zip(samples.dropFirst(),samples).reduce(Float(0)){max($0,abs($1.0-$1.1))}
        }
        // Use the actual source waveform as the limit, rather than treating a
        // high piano note's legitimate fast oscillations as a click.
        let reference=AudioController();try reference.prepareOffline()
        reference.configure(0,layer);reference.master(1);reference.space(0)
        var expected:Float=0
        for pedal in [false,true] {
            reference.panic();reference.sustain(pedal,layers:[layer])
            for strike in 0..<16 {
                let note=[84,96,100,108][strike%4]
                reference.noteOn(key:note,pitch:note,instrument:-1,layer:0,velocity:0.8)
                for block in 0..<23 {
                    if block==11 {reference.noteOff(key:note,channel:0)}
                    let b=try reference.offlineBlock()
                    expected=max(expected,maximumStep(Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)))))
                }
            }
        }
        reference.stop()
        let audio=AudioController();try audio.start();defer{audio.stop()}
        audio.configure(0,layer);audio.master(1);audio.space(0)
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        let recording=root.appendingPathComponent("realtime-piano.wav")
        var completion:Result<AudioDiagnosticRecorder.Summary,Error>?
        try audio.startAudioCheck(at:recording){completion=$0}
        for strike in 0..<32 {
            if strike==8 {audio.configure(1,layer);audio.gain(1,0)}
            if strike==16 {audio.sustain(true,layers:[layer])}
            let note=[84,96,100,108][strike%4]
            audio.noteOn(key:note,pitch:note,instrument:-1,layer:0,velocity:0.8)
            RunLoop.main.run(until:Date().addingTimeInterval(0.12))
            audio.noteOff(key:note,channel:0)
            RunLoop.main.run(until:Date().addingTimeInterval(0.12))
        }
        audio.stopAudioCheck()
        let deadline=Date().addingTimeInterval(5)
        while completion==nil && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
        guard let completion else {throw CocoaError(.fileReadUnknown)}
        _ = try completion.get()
        let capture=try AVAudioFile(forReading:recording)
        let buffer=AVAudioPCMBuffer(pcmFormat:capture.processingFormat,frameCapacity:AVAudioFrameCount(capture.length))!
        try capture.read(into:buffer)
        let samples=Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))
        let actual=maximumStep(samples)
        assert(samples.contains{abs($0)>0.01},"Live capture must contain the piano")
        assert(actual < expected*1.25+0.0001,"Live attack discontinuity exceeds the source: \(actual), offline \(expected)")
        let retained=try Data(contentsOf:file)
        assert(retained==bytes,"Original preset must remain unchanged")
        print("PASS: realtime upper-note attacks, second-instrument graph reload and sustain; live step \(actual), source reference \(expected)")
    }
}
