import Foundation
@main struct MainStageProcessingTests {
    static func main()throws {
        func device(_ name:String,_ values:[Float])->Data {
            let size=208+values.count*4
            var data=Data(repeating:0,count:size+36)
            data.replaceSubrange(0..<4,with:Data("UCuA".utf8))
            for i in 0..<4{data[28+i]=UInt8((size >> (i*8)) & 255)}
            data.replaceSubrange(156..<156+name.utf8.count,with:Data(name.utf8))
            data.replaceSubrange(168..<172,with:Data("GAME".utf8));data.replaceSubrange(220..<228,with:Data("GAMETSPP".utf8))
            for (index,value) in values.enumerated(){for i in 0..<4{data[236+index*4+i]=UInt8((value.bitPattern >> (i*8)) & 255)}}
            return data
        }
        var source=Data(repeating:0,count:36);source.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        source.append(device("Gain",[-6,0,0,0,0,0,0]))
        var eq:[Float]=[]
        for band in 0..<8{eq += [1,Float([79,198,265,630,1000,1900,4800,11000][band]),band==0 || band==7 ? 3:-2,0.707]}
        source.append(device("Chan EQ",eq));source.append(device("SilvVerb",[0,1,2]))
        let row:[String:Any]=["slot":0,"parameterIndex_1":0,"rangeLow":Float(-12),"rangeHigh":Float(0),"kSavedValueDoubleKey":Double(-6),"inputControlEvent":["type":5,"controllerID":71,"channelID":2]]
        let archive=try NSKeyedArchiver.archivedData(withRootObject:["7":[row]],requiringSecureCoding:false)
        for i in 0..<4{source.append(UInt8((archive.count >> (i*8)) & 255))};source.append(archive)
        let translated=try MainStageProcessing.translate(source)
        assert(translated.effects.map(\.kind)==[9,7] && translated.effects[0].values[0] == -6)
        assert(translated.effects[1].values[0]==79 && translated.effects[1].values[6]==265)
        assert(translated.issues.contains{$0.contains("SilvVerb")})
        assert(translated.macros.count==1 && translated.macros[0].midiCC==71 && translated.macros[0].midiChannel==2)
        var old=AudioEffect();old.kind=5
        var rack=try translated.appending(to:ImportedRack(effects:[old]))
        assert(rack.effects.map(\.kind)==[5,9,7] && rack.macros[0].bindings[0].effect==1)
        assert(!rack.applyMIDI(controller:71,value:127,channel:1))
        assert(rack.applyMIDI(controller:71,value:127,channel:2) && rack.effects[1].values[0]==0)
        let encoded=try JSONEncoder().encode(rack);let restored=try JSONDecoder().decode(ImportedRack.self,from:encoded)
        assert(restored==rack && restored.validate())
        var extended=Data(repeating:0,count:36);extended.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        var comp=[Float](repeating:0,count:25);comp[0] = -38;comp[1]=12;comp[2]=10;comp[3]=370;comp[4]=8.5;comp[24]=75
        extended.append(device("Comp",comp))
        var delay=[Float](repeating:0,count:26)
        delay[0]=20;delay[1]=25;delay[2]=565;delay[3]=750;delay[4]=35;delay[5]=35;delay[7]=30
        delay[22]=3300;delay[23]=72;delay[24]=2200;delay[25]=140
        extended.append(device("St-Delay",delay))
        let flipped:[String:Any]=["slot":0,"parameterIndex_1":0,"rangeLow":Float(-60),"rangeHigh":Float(0),"kSavedValueDoubleKey":Double(-38),"rangeIsFlipped":true,"controlName":"Compression","inputControlEvent":["type":5,"controllerID":74,"channelID":0]]
        let extra=try NSKeyedArchiver.archivedData(withRootObject:["2":[flipped]],requiringSecureCoding:false)
        for i in 0..<4{extended.append(UInt8((extra.count >> (i*8)) & 255))};extended.append(extra)
        let next=try MainStageProcessing.translate(extended)
        assert(next.effects.map(\.kind)==[6,3])
        assert(next.effects[0].values==[0,10,370,12,-38,0.75,8.5])
        let stereo=next.effects[1].importedDelay!
        assert(abs(stereo.left-0.565)<0.000001 && stereo.right==0.75 && stereo.leftChannel?.feedback==0.35 && stereo.rightChannel?.crossFeedback==0.3)
        assert(stereo.leftChannel?.lowCut==72 && stereo.rightChannel?.highCut==2200 && stereo.validate())
        var reversed=try next.appending(to:nil)
        assert(reversed.macros[0].name=="Compression")
        assert(reversed.applyMIDI(controller:74,value:0,channel:0) && reversed.effects[0].values[4]==0)
        assert(reversed.applyMIDI(controller:74,value:127,channel:0) && reversed.effects[0].values[4] == -60)
        let roundtrip=try JSONDecoder().decode(ImportedRack.self,from:JSONEncoder().encode(reversed));assert(roundtrip==reversed && roundtrip.validate())
        var synced=Data(repeating:0,count:36);synced.replaceSubrange(0..<4,with:Data("OCuA".utf8));delay[10]=1;synced.append(device("St-Delay",delay))
        let rejected=try MainStageProcessing.translate(synced);assert(rejected.effects.isEmpty && rejected.issues.contains{$0.contains("tempo-sync")})
        assert(MainStageProcessing.Draft(low:21,high:108,transpose:12).hasChanges)
        print("PASS: native compressor parameters, stereo delay manual times/feedback/filter/mix, reversed CC macros, roundtrip and unsupported sync rejection")
        print("PASS: active native MainStage gain/EQ translation, safe keyed-data decoding, linear macro/CC/channel routing, unknown effect retention and append without replacing existing processing")
    }
}
