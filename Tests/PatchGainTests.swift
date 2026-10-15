import Foundation
import AVFoundation
@main struct PatchGainTests {
 static func main() throws {
    let scratch=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
    try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:480000)!;buffer.frameLength=480000
    for i in 0..<480000 {buffer.floatChannelData![0][i]=0.2*sin(Float(i)*2 * .pi*261.626/48000)}
    let fileURL=scratch.appendingPathComponent("Sine.wav")
    do {let file=try AVAudioFile(forWriting:fileURL,settings:format.settings);try file.write(from:buffer)}
    let importer=AudioController();let sound=try importer.externalRack!.importSound(fileURL)
    func measure(_ db:Float) throws->Double {
        let audio=AudioController()
        var layer=Layer(name:"Sine",instrument:-1,gain:0.6);layer.external=sound
        audio.configure(0,layer);audio.gain(0,0.6);audio.setPatchVolume(db);audio.space(0);audio.master(0.5)
        try audio.prepareOffline();try audio.start()
        audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:1)
        for _ in 0..<20 {_ = try audio.offlineBlock()}
        var energy:Double=0;var count=0
        for _ in 0..<80 {let b=try audio.offlineBlock();for i in 0..<Int(b.frameLength) {let v=Double(b.floatChannelData![0][i]);energy+=v*v;count+=1}}
        return sqrt(energy/Double(count))
    }
    let baseline=try measure(0),boosted=try measure(6),reduced=try measure(-6)
    FileHandle.standardOutput.write(Data("RMS \(baseline), \(boosted), \(reduced) ratios \(boosted/baseline), \(reduced/baseline)\n".utf8))
    assert(baseline>0.0001 && boosted/baseline>1.9 && boosted/baseline<2.1)
    assert(reduced/baseline>0.45 && reduced/baseline<0.55)
    print("PASS imported instrument patch gain ±6 dB: ratios \(boosted/baseline), \(reduced/baseline)")
 }
}
