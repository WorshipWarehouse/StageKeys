import Foundation

/// Descriptor-driven stress of the actual C processors; no library sounds needed.
@main struct EffectStressTests {
    struct Evidence: Codable {
        let kind:Int, rate:Int, channels:Int, blocks:Int
        let peak:Float, worstRenderMilliseconds:Double
        let blocksOverNominalDeadline:Int
    }
    static func main() throws {
        let rounds=min(10000,max(1,Int(ProcessInfo.processInfo.environment["STAGEKEYS_EFFECT_STRESS_ROUNDS"] ?? "1") ?? 1))
        var rows:[Evidence]=[]
        for rate in [44100,48000,96000] {for kind in 1..<AudioEffectCatalog.names.count {for stereo in [false,true] {
            let left=sk_create_effects(Double(rate))!,right=sk_create_effects(Double(rate))!
            defer{sk_destroy(left);sk_destroy(right)}
            for state in [left,right] {sk_effect(state,0,0,Int32(kind),1)}
            let descriptors=AudioEffectCatalog.descriptors(for:kind)
            var a=[Float](repeating:0,count:257),b=a,peak:Float=0,worst=0.0,overruns=0,blocks=0,position=0
            for _ in 0..<rounds {for mode in 0..<3 {
                for state in [left,right] {for p in descriptors {
                    let value=mode==0 ? p.minimum:mode==1 ? p.defaultValue:p.maximum
                    sk_effect_parameter(state,0,0,Int32(p.index),value)
                }}
                // Irregular block boundaries, automation and an excited tail at every endpoint.
                for block in 0..<64 {
                    let frames=[1,31,64,127,257][block%5]
                    for i in 0..<frames {
                        let input:Float=block<32 ? 0.03*sin(Float(position)*2 * .pi*220/Float(rate)):0
                        a[i]=input;b[i]=input*0.7;position+=1
                    }
                    let start=DispatchTime.now().uptimeNanoseconds
                    if stereo {sk_process_effects_stereo(left,right,&a,&b,UInt32(frames))}
                    else {sk_process_effects(left,&a,UInt32(frames))}
                    let elapsed=Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
                    worst=max(worst,elapsed);blocks+=1
                    if elapsed>Double(frames)*1000/Double(rate){overruns+=1}
                    for i in 0..<frames {
                        precondition(a[i].isFinite && (!stereo || b[i].isFinite),"Invalid processor output kind \(kind)")
                        peak=max(peak,abs(a[i]),stereo ? abs(b[i]):0)
                    }
                }
                sk_panic(left);sk_panic(right)
                a=[Float](repeating:0,count:257);b=a
                if stereo {sk_process_effects_stereo(left,right,&a,&b,257)} else {sk_process_effects(left,&a,257)}
                precondition(a.allSatisfy{$0==0} && b.allSatisfy{$0==0},"Panic retained processor history kind \(kind)")
            }}
            rows.append(Evidence(kind:kind,rate:rate,channels:stereo ? 2:1,blocks:blocks,peak:peak,
                worstRenderMilliseconds:worst,blocksOverNominalDeadline:overruns))
        }}}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        print(String(decoding:try encoder.encode(rows),as:UTF8.self))
        print("PASS: all effect descriptors at min/default/max, three rates, mono/stereo, irregular blocks, finite output and Panic")
    }
}
