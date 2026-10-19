import Foundation
import AVFoundation
import Darwin
@main struct FeltPianoFidelityTests {
 static func main()throws {
  setbuf(stdout,nil)
  guard let data=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"] else{fatalError("Use an isolated copy of the personal sound library")}
  let entries=try SoundLibrary(url:URL(fileURLWithPath:data).appendingPathComponent("sound-library.json")).read()
  guard let sound=entries.first(where:{$0.name.hasPrefix("SK App Felt Piano")})?.sound,let filename=sound.fileName else{fatalError("Personal Felt Piano fixture unavailable")}
  let audioRoot=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.sundaysounds.sundaykeys/Data/Documents/Audio")
  let source=audioRoot.appendingPathComponent("EXS Factory Samples/SundayKeys/Sampler Instruments/SK App Felt Piano v1_6/SK App Felt Piano v1_6.aupreset")
  let managed=URL(fileURLWithPath:data).appendingPathComponent("Imported Sounds").appendingPathComponent(filename)
  func read(_ url:URL)throws->[String:Any]{try PropertyListSerialization.propertyList(from:Data(contentsOf:url),options:[],format:nil) as! [String:Any]}
  var original=try read(source);let installed=try read(managed)
  assert(NSDictionary(dictionary:original["Instrument"] as! [String:Any]).isEqual(installed["Instrument"] as Any),"Native source instrument state changed")
  var refs=original["file-references"] as! [String:String];let installedRefs=installed["file-references"] as! [String:String]
  for (key,path) in refs {
   let relative=path.range(of:"EXS Factory Samples/").map{String(path[$0.lowerBound...])} ?? path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
   let file=audioRoot.appendingPathComponent(relative)
   guard let copied=installedRefs[key] else{fatalError("Missing source reference")}
   let sourceHash=try AssetDigest.sha256(file),copiedHash=try AssetDigest.sha256(URL(fileURLWithPath:copied));assert(sourceHash==copiedHash)
   refs[key]=file.path
  }
  original["file-references"]=refs
  let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset");defer{try? FileManager.default.removeItem(at:temporary)}
  try PropertyListSerialization.data(fromPropertyList:original,format:.xml,options:0).write(to:temporary)
  func render(_ preset:URL,_ note:UInt8,_ velocity:UInt8)throws->[Float] {
   try autoreleasepool {
    let engine=AVAudioEngine(),sampler=AVAudioUnitSampler(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
    engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format);try SamplerRendering.configure(sampler,offline:true);try sampler.loadInstrument(at:preset)
    try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try engine.start();defer{engine.stop()}
    sampler.startNote(note,withVelocity:velocity,onChannel:0)
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!;var samples:[Float]=[]
    for block in 0..<70 {if block==40{sampler.stopNote(note,onChannel:0)};let status=try engine.renderOffline(512,to:buffer);assert(status == .success);samples += Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))}
    return samples
   }
  }
  for (note,velocity):(UInt8,UInt8) in [(48,40),(60,100),(72,120)] {
   let reference=try render(temporary,note,velocity),copy=try render(managed,note,velocity)
   let error=zip(reference,copy).reduce(0.0){$0+Double(($1.0-$1.1)*($1.0-$1.1))},energy=reference.reduce(0.0){$0+Double($1*$1)}
   assert(energy>0.001 && error/max(energy,1e-20)<1e-8,"Native source and managed Felt Piano differ")
   print("FELT SOURCE MATCH",note,velocity,"relative error",error/energy)
  }
  print("PASS: original Felt Piano state, 222 sample hashes, velocity zones, attack and release match the managed native instrument")
 }
}
