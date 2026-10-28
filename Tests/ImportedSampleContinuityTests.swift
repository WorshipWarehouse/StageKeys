import Foundation
import AVFoundation
/// A single-file sample imported through `externalRack` must render continuously.
/// Left streaming, the hosted sampler emitted ~250 ms of digital silence every
/// ~640 ms once a note was held, which is inaudible-adjacent only if you never
/// sustain a note; the same defect made a gain measurement nondeterministic.
@main struct ImportedSampleContinuityTests {
 static func main() throws {
    let scratch=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
    try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
    // Synthetic five-second sine. Nothing from the user's library is opened.
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:240000)!;buffer.frameLength=240000
    for i in 0..<240000 {buffer.floatChannelData![0][i]=0.2*sin(Float(i)*2 * .pi*261.626/48000)}
    let fileURL=scratch.appendingPathComponent("Sine.wav")
    do {let file=try AVAudioFile(forWriting:fileURL,settings:format.settings);try file.write(from:buffer)}
    let importer=AudioController();let sound=try importer.externalRack!.importSound(fileURL)
    let audio=AudioController();defer{audio.stop()}
    var layer=Layer(name:"Sine",instrument:-1,gain:0.6);layer.external=sound
    audio.configure(0,layer);audio.gain(0,0.6);audio.setPatchVolume(0);audio.space(0);audio.master(0.5)
    try audio.prepareOffline();try audio.start()
    audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:1)
    // 100 blocks is 1067 ms, long enough to contain the whole first dropout cycle.
    var run=0,longest=0,energy=0.0,frames=0
    for _ in 0..<100 {
        let block=try audio.offlineBlock()
        for i in 0..<Int(block.frameLength) {
            let left=block.floatChannelData![0][i],right=block.floatChannelData![1][i]
            if left == 0 && right == 0 {run+=1;longest=max(longest,run)} else {run=0}
            energy+=Double(left*left);frames+=1
        }
    }
    let rms=sqrt(energy/Double(frames))
    FileHandle.standardOutput.write(Data("longest silent run \(longest) frames, rms \(rms)\n".utf8))
    assert(rms>0.001,"the imported sample produced no measurable signal")
    assert(longest<480,"the imported sample dropped \(longest) frames of digital silence in a row")
    print("PASS sustained imported sample renders without silent gaps: longest run \(longest) frames, rms \(rms)")
 }
}
