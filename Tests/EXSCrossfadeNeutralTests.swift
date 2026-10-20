import Foundation
import AVFoundation
@main struct EXSCrossfadeNeutralTests {
 static func main()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let wave=root.appendingPathComponent("tone.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
  let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4800)!;pcm.frameLength=4800
  for i in 0..<4800{pcm.floatChannelData![0][i]=0.1*sin(Float(i)*2 * .pi*440/48000)}
  do{let f=try AVAudioFile(forWriting:wave,settings:format.settings);try f.write(from:pcm)}
  let original=try Data(contentsOf:wave)
  func put(_ b:inout [UInt8],_ at:Int,_ value:UInt32){for i in 0..<4{b[at+i]=UInt8(truncatingIfNeeded:value >> (i*8))}}
  func chunk(_ kind:UInt32,_ body:[UInt8])->Data {
   var h=[UInt8](repeating:0,count:84);put(&h,0,0x80000101 | kind << 24);put(&h,4,UInt32(body.count)|0x8000)
   h.replaceSubrange(16..<20,with:Array("TBOS".utf8));return Data(h+body)
  }
  func source(_ velocity:UInt8,_ key:UInt8)throws->URL {
   var z=[UInt8](repeating:0,count:96);z[1]=60;z[6]=60;z[7]=60;z[9]=1;z[10]=127;put(&z,16,4800)
   var g=[UInt8](repeating:0,count:120);g[5]=1;g[6]=127;g[32]=velocity;g[35]=key;put(&g,80,0xffffffff)
   var s=[UInt8](repeating:0,count:676);put(&s,4,4800);put(&s,8,48000)
   let directory=Array(root.path.utf8),name=Array("tone.wav".utf8);s.replaceSubrange(80..<80+directory.count,with:directory);s.replaceSubrange(336..<336+name.count,with:name)
   let file=root.appendingPathComponent("fixture-\(velocity)-\(key).exs");try (chunk(1,z)+chunk(2,g)+chunk(3,s)).write(to:file);return file
  }
  var baseline:NSDictionary?
  for (v,k) in [(UInt8(0),UInt8(0)),(128,0),(0,128),(128,128)] {
   let file=try source(v,k),output=root.appendingPathComponent("converted-\(v)-\(k).aupreset")
   let program=try EXSNative.convert(file,sampleRoot:root,to:output);assert(program.groups.count==1)
   let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:output),options:[],format:nil) as! [String:Any]
   let instrument=state["Instrument"] as! NSDictionary
   if let baseline{assert(baseline==instrument,"Neutral encodings changed the playback map")}else{baseline=instrument}
  }
  for (v,k) in [(UInt8(1),UInt8(128)),(127,128),(129,128),(128,1),(128,255)] {
   do{_ = try EXSNative.convert(source(v,k),sampleRoot:root,to:root.appendingPathComponent("rejected.aupreset"));fatalError("Active crossfade accepted")}
   catch{assert(error.localizedDescription.contains("crossfade"))}
  }
  let after=try Data(contentsOf:wave);assert(after==original)
  print("PASS: zero/biased-neutral crossfades produce identical maps; active values rejected; original sample bytes preserved")
 }
}
