import Foundation
import AVFoundation
@main struct PianoHeldNoteTests {
 static func main()throws {
  guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"] else{return}
  let source=URL(fileURLWithPath:path),bytes=try Data(contentsOf:source)
  let state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
  let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data)
  assert(program.conversionVersion==5,"Use the repaired native EXS fixture")
  let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!),folder=root.appendingPathComponent("Imported Sounds")
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try bytes.write(to:folder.appendingPathComponent(source.lastPathComponent))
  let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
  var layer=Layer(name:"Held Steinway",instrument:-1,gain:1)
  layer.external=ExternalSound(kind:.samplerPreset,name:layer.name,fileName:source.lastPathComponent,nativeSampler:program)
        if let value=ProcessInfo.processInfo.environment["STAGEKEYS_HOST_CURVE"],let curve=Int(value) {var rack=program.rack;rack.mainStageAmplitudeVelocityCurve=curve;layer.importedRack=rack}
  audio.configure(0,layer);audio.master(1);audio.space(0)
  for note in [74,86] {
   audio.panic();audio.sustain(false,layers:[layer]);for _ in 0..<50 {_ = try audio.offlineBlock()}
   audio.noteOn(key:note,pitch:note,instrument:-1,layer:0,velocity:83.0/127)
   var tail:[Float]=[]
   var frames=0,energy=Array(repeating:Double(0),count:16),counts=Array(repeating:0,count:16),peaks=Array(repeating:Float(0),count:16)
   while frames<48000*15 {
    let b=try audio.offlineBlock()
    for i in 0..<Int(b.frameLength) {let second=min(15,(frames+i)/48000),value=b.floatChannelData![0][i];assert(value.isFinite);if (frames+i)>=134400 && (frames+i)<158400 {tail.append(value)};energy[second]+=Double(value*value);counts[second]+=1;peaks[second]=max(peaks[second],abs(value))}
    frames+=Int(b.frameLength)
   }
   print("Held MIDI \(note) RMS by second",zip(energy,counts).map{$0.1>0 ? sqrt($0.0/Double($0.1)):0},"peaks",peaks)
   func band(_ center:Double)->Double {
    var peak=0.0
    for offset in -10...10 {
     let omega=2*Double.pi*(center+Double(offset))/48000
     var real=0.0,imaginary=0.0
     for i in tail.indices {let sample=Double(tail[i])*(0.5-0.5*cos(2*Double.pi*Double(i)/Double(tail.count-1)));real+=sample*cos(omega*Double(i));imaginary+=sample*sin(omega*Double(i))}
     peak=max(peak,hypot(real,imaginary))
    }
    return peak
   }
   let fundamental=440*pow(2,Double(note-69)/12),correct=band(fundamental),foreign=band(fundamental*sqrt(2))
   print("Tail pitch bands MIDI \(note): correct \(correct), foreign \(foreign)")
   assert(correct>0.000001 && foreign<correct*0.15,"Tail must keep the played pitch, not the neighboring sample heard in the user capture")
   assert(peaks[0]>0.001,"The requested held note must sound")
   assert(peaks[10...14].allSatisfy{$0<0.000001},"This zero-sustain Steinway must not retrigger a neighboring sample after ten seconds")
   audio.noteOff(key:note,channel:0)
  }
  print("PASS: 15-second D5 holds in both octave naming conventions have no late neighboring-note attack")
 }
}
