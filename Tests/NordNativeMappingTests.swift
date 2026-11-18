import Foundation
import AVFoundation

/// Original encoded sine fixtures: no vendor PCM or private paths.
@main struct NordNativeMappingTests {
    @MainActor static func main() throws {
        var bytes=TestFixtures.nordPiano()
        for key in [36,96] {bytes[44+0x8c+key]=60}
        bytes[44+0x18c+60]=20 // documented 14-cent translation at the stored root
        var crc:UInt32=0xffffffff
        for byte in bytes.dropFirst(44) {crc ^= UInt32(byte);for _ in 0..<8 {crc=(crc&1 != 0) ? (crc>>1)^0xedb88320:crc>>1}}
        crc ^= 0xffffffff
        for i in 0..<4 {bytes[24+i]=UInt8(truncatingIfNeeded:crc>>(i*8))}
        let preview=try NordNative.preview(bytes)
        assert(preview.zones.count==10)
        for key in [36,59,60,61,96] {
            let zones=preview.zones.filter{$0.key==key}
            assert(zones.map(\.velocityLow)==[1,58] && zones.map(\.velocityHigh)==[57,127])
            assert(zones.map(\.stroke)==[1,0])
        }
        let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
        let rack=audio.externalRack!
        let prepared=try NordNative.prepare(bytes,preview:preview,library:rack.libraryURL,template:NordNative.template())
        var layer=Layer(name:"Generated Nord mapping",instrument:-1,gain:0.65);layer.external=prepared.sound
        assert(audio.configure(0,layer))
        audio.gain(0,0.65,seconds:0);audio.master(0.1);audio.space(0)
        let map=try StageKeysSampler.map(prepared.sound,library:rack.libraryURL)
        assert(map.zones.count==10 && map.zones.allSatisfy{$0.root==60 && $0.looped})
        let preset=try PropertyListSerialization.propertyList(from:Data(contentsOf:rack.libraryURL.appendingPathComponent(prepared.sound.fileName!)),options:[],format:nil) as! [String:Any]
        let references=preset["file-references"] as! [String:String]
        for (i,stroke) in preview.index.strokes.enumerated() {
            let raw=try NordPiano.decode(bytes,stroke:stroke,channels:2)
            let expected=(0..<stroke.frames).flatMap {frame->[Int16] in
                let sample=Int16(sin(Double(frame)*2*Double.pi/128)*Double(i==0 ? 8000:2000))
                return [sample,-sample/2]
            }
            assert(raw==expected,"Decoded stereo frames must match the independent sine fixture")
            let file=URL(fileURLWithPath:references["Sample:\(0x10000000+i)"]!)
            assert((try! Data(contentsOf:file))==NordNative.wav(expected,channels:2))
            let opened=try AVAudioFile(forReading:file)
            assert(opened.length==stroke.frames && opened.processingFormat.channelCount==2)
        }
        func render(_ blocks:Int)throws->[Float] {
            var values:[Float]=[]
            for _ in 0..<blocks {
                let block=try audio.offlineBlock()
                for c in 0..<Int(block.format.channelCount) {for f in 0..<Int(block.frameLength) {assert(block.floatChannelData![c][f].isFinite)}}
                values += Array(UnsafeBufferPointer(start:block.floatChannelData![0],count:Int(block.frameLength)))
            }
            return values
        }
        func rms(_ values:[Float])->Double {sqrt(values.reduce(0.0){$0+Double($1)*Double($1)}/Double(max(1,values.count)))}
        func frequency(_ values:[Float])->Double {
            let start=values.count/2
            var crossings:[Double]=[]
            for i in max(1,start)..<values.count where values[i-1]<0 && values[i]>=0 {
                crossings.append(Double(i-1)+Double(-values[i-1]/(values[i]-values[i-1])))
            }
            assert(crossings.count>10)
            return Double(crossings.count-1)*48000/(crossings.last!-crossings.first!)
        }
        var levels:[Int:Double]=[:]
        for key in [36,60,96] {for velocity in [20,57,58,110,127] {
            audio.panic();_ = try render(5)
            rack.noteOn(channel:0,key:key,pitch:key,velocity:Float(velocity)/127,sourceID:1)
            let values=try render(100),level=rms(Array(values.suffix(24000)))
            assert(level>0.00001,"A covered register/velocity must play")
            let expected=35002.0/128*pow(2,Double(key-60)/12+(key==60 ? 14.0:0)/1200)
            let measured=frequency(values)
            assert(abs(1200*log2(measured/expected))<8,"Register/tuning mismatch: key \(key), expected \(expected), got \(measured)")
            if key==60 {levels[velocity]=level}
            rack.noteOff(channel:0,key:key)
            let released=try render(100)
            assert(rms(Array(released.suffix(12000)))<level*0.02,"Released loops must decay")
            assert(rack.debugNoteIntentCount(0)==0)
        }}
        assert(levels[58]!/levels[57]!>3,"The stored velocity boundary must change the actual played recording")
        for _ in 0..<3 {
            rack.sustain(channel:0,on:true)
            rack.noteOn(channel:0,key:60,pitch:60,velocity:0.8,sourceID:1)
            _ = try render(5);rack.noteOff(channel:0,key:60)
            let held=try render(60)
            assert(rms(Array(held.suffix(12000)))>0.0001 && rack.debugNoteIntentCount(0)==1)
            rack.sustain(channel:0,on:false)
            let released=try render(100)
            assert(rms(Array(released.suffix(12000)))<0.00001 && rack.debugNoteIntentCount(0)==0)
        }
        for key in [0,127] {
            audio.panic();_ = try render(5)
            rack.noteOn(channel:0,key:key,pitch:key,velocity:1)
            let uncovered=try render(50)
            assert(rms(uncovered)<0.000001,"Uncovered keys must stay silent")
            rack.noteOff(channel:0,key:key)
        }
        print("PASS Nord mapping: exact stereo PCM, low/middle/high register, tuning, velocity boundary, repeated sustain/release loops and uncovered silence")
    }
}
