import Foundation
import AVFoundation
@main struct PianoFidelityTests {
 static func main() throws {
  guard let fixture=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"] else {print("SKIP: private piano fixture unset");return}
  let file=URL(fileURLWithPath:fixture),state=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as! [String:Any]
  let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data)
  let destination=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("Imported Sounds",isDirectory:true)
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true);try Data(contentsOf:file).write(to:destination.appendingPathComponent(file.lastPathComponent))
  let audio=AudioController();try audio.prepareOffline()
  var layer=Layer(name:"Piano fidelity fixture",instrument:-1,gain:0.5)
  layer.external=ExternalSound(kind:.samplerPreset,name:layer.name,fileName:file.lastPathComponent,nativeSampler:program)
  audio.configure(0,layer);audio.master(1);audio.space(0)
  for _ in 0..<10 {_ = try audio.offlineBlock()}
  for wet in [false,true] {
  var reverb=AudioEffect();reverb.kind=15;reverb.parameters=AudioEffectCatalog.defaults(for:15);reverb.enabled=wet
  layer.effects=[AudioEffect(),AudioEffect(),reverb];audio.configure(0,layer)
  for velocity:Float in [0.3,0.65,1] {
   audio.panic(); for _ in 0..<10 {_ = try audio.offlineBlock()}
   for note in [48,52,55,60,64,67] {audio.noteOn(key:note,pitch:note,instrument:-1,layer:0,velocity:velocity)}
   var peak:Float=0,delta:Float=0,previous:Float=0,energy:Double=0
   for _ in 0..<50 {let b=try audio.offlineBlock();for i in 0..<Int(b.frameLength){let v=b.floatChannelData![0][i];assert(v.isFinite);peak=max(peak,abs(v));delta=max(delta,abs(v-previous));previous=v;energy+=Double(v*v)}}
   print("Piano wet \(wet) velocity \(velocity): peak \(peak), max sample step \(delta), energy \(energy)")
   assert(energy>0.00001 && peak<0.95 && delta<0.15,"Piano attack must remain finite and below clipping")
  }
  audio.panic();audio.sustain(true,layers:[layer]);var sustainedPeak:Float=0
  for strike in 0..<12 {
   for note in [48,52,55,60,64,67] {let key=strike*128+note;audio.noteOn(key:key,pitch:note,instrument:-1,layer:0,velocity:1);audio.noteOff(key:key,channel:0)}
   for _ in 0..<10 {let b=try audio.offlineBlock();for c in 0..<2 {for i in 0..<Int(b.frameLength){let v=b.floatChannelData![c][i];assert(v.isFinite);sustainedPeak=max(sustainedPeak,abs(v))}}}
  }
  assert(sustainedPeak<0.95,"Repeated sustained piano chords must not digitally clip")
  print("Piano wet \(wet) repeated sustain peak \(sustainedPeak)")
  audio.sustain(false,layers:[layer]);audio.panic()
  }
 }
}
