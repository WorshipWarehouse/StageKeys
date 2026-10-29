import Foundation
import AVFoundation

@main struct OutputMeterTests {
    static func main() throws {
        let meter=OutputMeter(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4)!;buffer.frameLength=4
        let l:[Float]=[0.5,-0.5,1,-1],r:[Float]=[0.25,-0.25,0,0]
        for i in 0..<4{buffer.floatChannelData![0][i]=l[i];buffer.floatChannelData![1][i]=r[i]}
        meter.append(buffer);let reading=meter.read()
        assert(reading.peak==1 && reading.frames==4 && reading.overload==2 && reading.invalid==0)
        assert(abs(reading.rms-sqrt(2.625/8))<1e-6)
        for i in 0..<4{assert(buffer.floatChannelData![0][i]==l[i] && buffer.floatChannelData![1][i]==r[i])}
        buffer.floatChannelData![0][0] = .nan;buffer.floatChannelData![1][0] = .infinity
        meter.append(buffer);assert(meter.read().invalid==2 && meter.read().rms.isFinite)
        let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
        let layer=TestFixtures.layer(gain:0.1,name:"Meter Probe")
        audio.configure(0,layer);audio.gain(0,0.1,seconds:0);audio.master(1);audio.space(0)
        audio.noteOn(key:60,pitch:60,instrument:0,layer:0,velocity:0.7)
        for _ in 0..<100{_ = try audio.offlineBlock()}
        let deadline=Date().addingTimeInterval(2)
        while audio.outputMetrics.frames==0 && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        assert(audio.outputMetrics.frames>0 && audio.outputMetrics.invalid==0)
        print("PASS: final output tap delivers metrics; meter preserves audio and reports overload/non-finite samples")
    }
}
