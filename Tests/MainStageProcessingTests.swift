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
        print("PASS: active native MainStage gain/EQ translation, safe keyed-data decoding, linear macro/CC/channel routing, unknown effect retention and append without replacing existing processing")
    }
}
