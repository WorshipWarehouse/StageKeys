import Foundation
import AVFoundation
import Darwin
@main struct ParallelAudioTests {
 static func main()throws {
 setbuf(stdout,nil)
 let engine=AVAudioEngine(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
 let source=AVAudioSourceNode(format:format){_,_,frames,list in for buffer in UnsafeMutableAudioBufferListPointer(list){let p=buffer.mData!.assumingMemoryBound(to:Float.self);for i in 0..<Int(frames){p[i]=0.1}};return 0}
 func gain(_ db:Float)->AudioEffect{var fx=AudioEffect();fx.kind=9;fx.parameters=[db];return fx}
 var rack=ImportedRack(audioRacks:[ImportedAudioRack(beforeEffect:1,name:"Dry + Wet",branches:[ImportedAudioBranch(name:"Dry",rack:ImportedRack(effects:[gain(-6.0206)])),ImportedAudioBranch(name:"Wet",rack:ImportedRack(audioRacks:[ImportedAudioRack(beforeEffect:0,name:"Nested",branches:[ImportedAudioBranch(name:"Nested Dry",rack:ImportedRack(effects:[gain(-6.0206)])),ImportedAudioBranch(name:"Nested Wet",rack:ImportedRack(effects:[gain(-6.0206)]))])],effects:[gain(-6.0206)]))])],effects:[gain(-6),gain(6)])
 let graph=ImportedAudioGraph(engine:engine,rack:rack,format:format,tempo:120)
 engine.attach(source);engine.connect(source,to:graph.input,format:format);engine.connect(graph.output,to:engine.mainMixerNode,format:format)
 try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try engine.start()
 func level()throws->Float{let b=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!;for _ in 0..<10{try engine.renderOffline(512,to:b)};return b.floatChannelData![0][200]}
 let loud=try level();print("SPLIT INITIAL",loud);assert(abs(loud-0.1)<0.001,"Parallel sum or serial order failed")
 rack.audioRacks![0].branches[1].enabled=false;graph.configure(rack,tempo:120);let half=try level();assert(abs(half/loud-0.5)<0.01,"One fan-out branch replaced another")
 rack.effects[0]=gain(-60);graph.configure(rack,tempo:120);let quiet=try level();print("AUDIO PARAM",loud,half,quiet);assert(abs(quiet)<abs(loud)*0.002)
 assert(rack.validate());let decoded=try JSONDecoder().decode(ImportedRack.self,from:JSONEncoder().encode(rack));assert(decoded==rack)
 var macroRack=rack;macroRack.macros=[ImportedMacro(index:0,name:"Branch",value:127,bindings:[ImportedMacroBinding(audioPath:[0,0],effect:0,parameter:0,minimum:-60,maximum:0)])];assert(macroRack.validate());macroRack.setMacro(0,value:0);assert(macroRack.audioRacks![0].branches[0].rack.effects[0].values[0] == -60)
 engine.stop()
 print("PASS: parallel audio graph parameter updates")
 }
}
