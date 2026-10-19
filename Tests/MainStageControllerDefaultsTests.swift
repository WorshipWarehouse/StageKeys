import Foundation
import AVFoundation
@main struct MainStageControllerDefaultsTests {
 static func main()throws {
  let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,buffer=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,frameCapacity:96000)!
  buffer.frameLength=96000;for i in 0..<96000{buffer.floatChannelData![0][i]=0.03*sin(Float(i)*2 * .pi*440/48000)}
  let file=root.appendingPathComponent("original.wav");do{let out=try AVAudioFile(forWriting:file,settings:format.settings);try out.write(from:buffer)};let original=try Data(contentsOf:file)
  let importer=AudioController(),sound=try importer.externalRack!.importSound(file)
  func measure(_ mainstage:Bool,received:UInt8?=nil)throws->Double {
   let audio=AudioController();try audio.prepareOffline();defer{audio.stop()};audio.bypassMasterLimiter(true)
   var layer=Layer(name:"Fixture",instrument:-1,gain:1);layer.external=sound
   if mainstage {layer.importedRack=try MainStageProcessing.Draft().appending(to:nil)}
   audio.configure(0,layer);audio.gain(0,1);audio.master(1);audio.space(0)
   if let received {audio.externalRack?.control(channel:0,controller:7,value:received);audio.configure(0,layer)}
   audio.panic();audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:1)
   var e=0.0;for j in 0..<60{let b=try audio.offlineBlock();if j>5{for i in 0..<Int(b.frameLength){let v=Double(b.floatChannelData![0][i]);e+=v*v}}};return sqrt(e)
  }
  let standard=try measure(false),unity=try measure(true),received=try measure(true,received:100)
  assert(standard>0 && unity/standard>1.5 && unity/standard<1.7,"MainStage source must start at unity, including ordinary system-loaded samplers")
  assert(abs(received/standard-1)<0.001,"Actual MIDI CC7 must survive rack reconfiguration and panic")
  let retained=try Data(contentsOf:file);assert(retained==original)
  print("PASS: MainStage unity controller defaults, rendered gain ratio \(unity/standard), received-controller preservation and unchanged source bytes")
 }
}
