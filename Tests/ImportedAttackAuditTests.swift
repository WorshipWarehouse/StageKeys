import Foundation
import AVFoundation
import Darwin
@main struct ImportedAttackAuditTests {
 static func main()throws {
  setbuf(stdout,nil)
  guard let audit=ProcessInfo.processInfo.environment["STAGEKEYS_ATTACK_AUDIT"] else {print("SKIP: optional installed-sound audit fixture unset");return}
  let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:audit))) as! [[String:Any]]
  for c in cases {
   let file=URL(fileURLWithPath:c["preset"] as! String),bytes=try Data(contentsOf:file),state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
   assert(NSDictionary(dictionary:SamplerAttack.prepare(state,minimum:0)).isEqual(to:state))
  }
  func render(_ file:URL,_ rackMode:Bool,_ note:UInt8)throws->[Float] {
   try autoreleasepool {
    let engine=AVAudioEngine(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
    try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512)
    var rack:ExternalInstrumentRack?,sampler:AVAudioUnitSampler?
    if rackMode {
     let instrument=try ExternalInstrumentRack(engine:engine,libraryURL:file.deletingLastPathComponent());rack=instrument
     var failure:Error?;instrument.load(ExternalSound(kind:.samplerPreset,name:"Audit",fileName:file.lastPathComponent),channel:0){if case .failure(let e)=$0{failure=e}};if let failure{throw failure}
     instrument.volume(channel:0,gain:1,pan:0);try instrument.prepareOfflineSamples()
    }else {
     let unit=AVAudioUnitSampler();sampler=unit;engine.attach(unit);engine.connect(unit,to:engine.mainMixerNode,format:format)
     try SamplerRendering.configure(unit,offline:true);try unit.loadInstrument(at:file)
    }
    try engine.start();defer{engine.stop()}
    rack?.processing(channel:0,gain:1,cutoff:20000,resonance:0.707,eqEnabled:false,bands:EQBand.defaults.map{($0.frequency,$0.gain,$0.q)},compressorEnabled:false,threshold:-18,attack:0.02,release:0.15,makeup:0)
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
    for _ in 0..<10 {_ = try engine.renderOffline(512,to:buffer)}
    if let rack {rack.noteOn(channel:0,key:Int(note),pitch:Int(note),velocity:100/127)}else{sampler!.startNote(note,withVelocity:100,onChannel:0)}
    var samples:[Float]=[]
    for _ in 0..<30 {_ = try engine.renderOffline(512,to:buffer);samples+=Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))}
    return samples
   }
  }
  var checked=0
  for name in ["SK App Felt Piano","SK Una Corda Felt 2","SK App SK Glockenspiel","Touchstone Piano","Airy EP","Sunrise Pad"] {
   guard let c=cases.first(where:{($0["name"] as! String).hasPrefix(name)}) else{continue}
   let file=URL(fileURLWithPath:c["preset"] as! String),bytes=try Data(contentsOf:file)
   for note:UInt8 in [60,84] {
    let rawA=try render(file,false,note),rawB=try render(file,true,note)
    let startA=rawA.firstIndex(where:{abs($0)>1e-9}) ?? 0,startB=rawB.firstIndex(where:{abs($0)>1e-9}) ?? 0
    let count=min(rawA.count-startA,rawB.count-startB),a=Array(rawA[startA..<startA+count]),b=Array(rawB[startB..<startB+count])
    print("ONSET",name,note,startA,startB)
    let aa=a.reduce(0.0){$0+Double($1*$1)},ab=zip(a,b).reduce(0.0){$0+Double($1.0*$1.1)}
    guard aa>1e-9 else{continue}
    let gain=ab/aa,error=zip(a,b).reduce(0.0){$0+pow(Double($1.1)-Double($1.0)*gain,2)},energy=b.reduce(0.0){$0+Double($1*$1)}
    var best=error/max(energy,1e-20),bestLag=0
    for lag in -48...48 {
     let lo=max(0,-lag),hi=min(a.count,b.count-lag,4000);guard hi>lo else{continue}
     var aa=0.0,ab=0.0,bb=0.0
     for i in lo..<hi {let x=Double(a[i]),y=Double(b[i+lag]);aa+=x*x;ab+=x*y;bb+=y*y}
     let residual=1-ab*ab/max(aa*bb,1e-30)
     if residual<best {best=residual;bestLag=lag}
    }
    // The host graph has a fractional-sample delay relative to a direct AU.
    // Align that delay with a windowed-sinc comparison; do not misclassify
    // phase from graph timing as a changed sample/attack.
    let integerLag=bestLag
    for f in -16...16 {
     let fraction=Double(f)/32,delay=Double(integerLag)+fraction,base=Int(floor(delay)),part=delay-Double(base)
     var weights:[Double]=[]
     for tap in -8...8 {let distance=Double(tap)-part;let sinc=abs(distance)<1e-12 ? 1:sin(.pi*distance)/(.pi*distance);let window=abs(distance)<8 ? (abs(distance)<1e-12 ? 1:sin(.pi*distance/8)/(.pi*distance/8)):0;weights.append(sinc*window)}
     let norm=weights.reduce(0,+);weights=weights.map{$0/norm}
     let lo=64,hi=min(a.count-64,b.count-base-64,4000);var aa=0.0,ab=0.0,bb=0.0
     for i in lo..<hi {var y=0.0;for tap in -8...8 {y+=Double(b[i+base+tap])*weights[tap+8]};let x=Double(a[i]);aa+=x*x;ab+=x*y;bb+=y*y}
     let residual=1-ab*ab/max(aa*bb,1e-30)
     if residual<best {best=residual}
    }
    print("CORRELATION",name,note,"best residual",best,"lag",bestLag)
    assert(b.allSatisfy(\.isFinite) && best<0.0001,"Imported attack differs from original native preset: \(name), \(note), \(best)")
    let peakStepA=(1..<min(720,a.count)).map{abs(a[$0]-a[$0-1])}.max()!,peakStepB=(1..<min(720,b.count)).map{abs(b[$0]-b[$0-1])}.max()!
    let level=sqrt(energy/max(aa,1e-20))
    assert(Double(peakStepB)<Double(peakStepA)*level*1.5,"Unexpected new attack discontinuity")
    checked+=1;print("PASS original attack shape",name,note,"latency-aligned residual",best)
   }
   let retained=try Data(contentsOf:file);assert(retained==bytes)
  }
  assert(checked>=6)
  print("PASS:",cases.count,"installed preset states audited,",checked,"middle/upper-register original-vs-production waveform checks")
 }
}
