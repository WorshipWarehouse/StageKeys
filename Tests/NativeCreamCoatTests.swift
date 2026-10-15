import AVFoundation
import Foundation
@main struct NativeCreamCoatTests {
 static func main()throws {
  let rate=48000.0,format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
  let engine=AVAudioEngine(),unit=BuiltinEffectUnit.make()
  let native=unit.auAudioUnit as! BuiltinEffectUnit
  var fx=AudioEffect();fx.kind=13;fx.parameters=[0,18,0.33,776,2884,0,0,0,1,1];fx.reverbCore="creamcoat"
  native.configure(slot:0,kind:13,enabled:true,values:fx.renderValues,tempo:120)
  var cursor=0
  let source=AVAudioSourceNode(format:format){_,_,frames,list in
   for b in UnsafeMutableAudioBufferListPointer(list){let p=b.mData!.assumingMemoryBound(to:Float.self);for i in 0..<Int(frames){p[i]=cursor+i==0 ? 0.1:0}}
   cursor+=Int(frames);return 0
  }
  engine.attach(source);engine.attach(unit);engine.connect(source,to:unit,format:format);engine.connect(unit,to:engine.mainMixerNode,format:format)
  try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try engine.start()
  let left=sk_create_effects(rate)!,right=sk_create_effects(rate)!;defer{engine.stop();sk_destroy(left);sk_destroy(right)}
  for p in [left,right]{sk_effect(p,0,0,13,1);for (i,value) in fx.renderValues.enumerated(){sk_effect_parameter(p,0,0,Int32(i),value)}}
  let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
  var error=0.0,energy=0.0,first:Int?
  for block in 0..<64 {
   guard try engine.renderOffline(512,to:buffer) == .success else {fatalError("Offline render failed")}
   var l=Array(repeating:Float(0),count:512),r=l;if block==0{l[0]=0.1;r[0]=0.1}
   sk_process_effects_stereo(left,right,&l,&r,512)
   for channel in 0..<2 {let expected=channel==0 ? l:r;for i in 0..<512{let actual=buffer.floatChannelData![channel][i];assert(actual.isFinite);let delta=Double(actual-expected[i]);error+=delta*delta;energy+=Double(expected[i])*Double(expected[i]);if first==nil && abs(actual)>1e-6 {first=block*512+i}}}
  }
  assert(energy>1e-5 && error/energy<1e-10,"Native effect unit dropped the source core or altered its parameters")
  assert(first==3215,"Native source predelay did not reach the audio graph")
  print("PASS: native Audio Unit matches direct stereo core, normalized predelay onset 3215, relative error",error/energy)
 }
}
