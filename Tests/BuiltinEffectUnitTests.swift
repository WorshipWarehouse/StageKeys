import Foundation
import AVFoundation
@main struct BuiltinEffectUnitTests {
 static func main() throws {
    func render(_ kind:Int,enabled:Bool=true,rate:Double=48000,stopAfter:Int?=nil) throws->[Float] {
        let engine=AVAudioEngine(),effect=BuiltinEffectUnit.make()
        let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!
        var phase:Double=0;var sourceFrame=0
        let source=AVAudioSourceNode(format:format){flags,_,frames,list in
            let buffers=UnsafeMutableAudioBufferListPointer(list)
            let silent=stopAfter.map{sourceFrame >= $0} ?? false
            for frame in 0..<Int(frames){let v:Float=(stopAfter.map{sourceFrame >= $0} ?? false) ? 0:Float(0.1*sin(phase)+0.04*sin(phase*3));phase+=2 * .pi*440/rate;sourceFrame+=1;for c in 0..<2 {buffers[c].mData!.assumingMemoryBound(to:Float.self)[frame]=v}}
            flags.pointee=ObjCBool(silent)
            return noErr
        }
        engine.attach(source);engine.attach(effect);engine.connect(source,to:effect,format:format);engine.connect(effect,to:engine.mainMixerNode,format:format)
        let unit=effect.auAudioUnit as! BuiltinEffectUnit
        var values=AudioEffectCatalog.defaults(for:kind)
        let changes:[Int:(Int,Float)]=[1:(0,600),2:(0,0.8),3:(1,0.25),4:(0,4),5:(0,0.68),6:(5,1),7:(7,12),8:(0,0.2),9:(0,-12),10:(8,0.6),11:(0,0.96),12:(1,1),13:(0,0.5),14:(0,2),15:(0,20)]
        if let (index,value)=changes[kind]{values[index]=value}
        unit.configure(slot:0,kind:kind,enabled:enabled,values:values,tempo:120)
        try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);engine.prepare();try engine.start()
        defer{engine.stop()}
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
        var result:[Float]=[]
        for _ in 0..<94 {
            let status=try engine.renderOffline(512,to:buffer);assert(status == .success)
            for i in 0..<Int(buffer.frameLength){let value=buffer.floatChannelData![0][i];assert(value.isFinite && abs(value)<=16);result.append(value)}
        }
        return result
    }
    let dry=try render(0)
    for kind in 1...15 {
        let wet=try render(kind),bypass=try render(kind,enabled:false)
        let difference=zip(dry,wet).reduce(Double(0)){$0+pow(Double($1.0-$1.1),2)}
        let bypassDifference=zip(dry,bypass).reduce(Double(0)){$0+pow(Double($1.0-$1.1),2)}
        assert(difference>0.001,"Effect \(kind) must alter incoming audio")
        assert(bypassDifference<1e-8,"Bypass must preserve incoming audio")
        print("PASS built-in AU effect \(kind): audible, finite, transparent bypass")
    }
    let tail=try render(3,stopAfter:12000),silentDry=try render(0,stopAfter:12000)
    assert(tail.suffix(12000).reduce(Float(0)){$0+abs($1)}>0.001)
    assert(silentDry.suffix(12000).allSatisfy{$0==0})
    _ = try render(10,rate:44100)
    print("PASS built-in AU render at 44.1 and 48 kHz")
 }
}
