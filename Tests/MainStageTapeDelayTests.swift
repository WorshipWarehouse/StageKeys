import Foundation
@main struct MainStageTapeDelayTests {
    static func main()throws {
        func strip(_ values:[Float])->Data {
            let size=208+values.count*4
            var device=Data(repeating:0,count:size+36)
            device.replaceSubrange(0..<4,with:Data("UCuA".utf8))
            for i in 0..<4{device[28+i]=UInt8(truncatingIfNeeded:size >> (i*8))}
            device.replaceSubrange(156..<166,with:Data("Tape Delay".utf8));device.replaceSubrange(168..<172,with:Data("GAME".utf8));device.replaceSubrange(220..<228,with:Data("GAMETSPP".utf8))
            for (index,value) in values.enumerated(){for i in 0..<4{device[236+index*4+i]=UInt8(truncatingIfNeeded:value.bitPattern >> (i*8))}}
            var data=Data(repeating:0,count:36);data.replaceSubrange(0..<4,with:Data("OCuA".utf8));data.append(device);return data
        }
        let measured:[Float]=[0,0,0,51,1900,170,1,4,0,40,0,0,0.2,0,0,120,0,0,0,100,0]
        let source=strip(measured),hash=MainStagePatch.digest(source)
        let synced=try MainStageProcessing.translate(source)
        assert(synced.effects.count==1 && synced.effects[0].importedDelay?.left==1 && synced.effects[0].importedDelay?.leftSynced==true)
        assert(synced.effects[0].importedDelay?.dryGain==1 && synced.effects[0].importedDelay?.wetGain==0)
        assert(abs(synced.effects[0].values[0]-0.51)<0.00001)
        var values=measured;values[6]=0;values[7]=8;values[8]=4;values[19]=70;values[20]=1
        var free=strip(values)
        let rows:[String:Any]=["1":[["slot":0,"parameterIndex_1":19,"rangeLow":Float(0),"rangeHigh":Float(100),"kSavedValueDoubleKey":Double(70),"inputControlEvent":["type":5,"controllerID":74,"channelID":2]]],"2":[["slot":0,"parameterIndex_1":20,"rangeLow":Float(0),"rangeHigh":Float(100),"kSavedValueDoubleKey":Double(1),"inputControlEvent":["type":5,"controllerID":75,"channelID":2]]]]
        let archive=try NSKeyedArchiver.archivedData(withRootObject:rows,requiringSecureCoding:false)
        for i in 0..<4{free.append(UInt8(truncatingIfNeeded:archive.count >> (i*8)))};free.append(archive)
        var rack=try MainStageProcessing.translate(free).appending(to:nil)
        let delay=rack.effects[0].importedDelay!
        assert(abs(delay.left-0.26)<0.000001 && !delay.leftSynced && delay.lowCut==170 && delay.highCut==1900)
        assert(delay.dryGain==0.7 && delay.wetGain==0.01 && rack.macros.count==2 && rack.validate())
        assert(rack.applyMIDI(controller:74,value:0,channel:2) && rack.effects[0].importedDelay?.dryGain==0)
        assert(rack.applyMIDI(controller:75,value:127,channel:2) && rack.effects[0].importedDelay?.wetGain==1)
        let encoded=try JSONEncoder().encode(rack),restored=try JSONDecoder().decode(ImportedRack.self,from:encoded)
        assert(restored==rack && restored.validate())
        for index in [1,2,10,11,14,16,17,18] {
            var unsupported=measured;unsupported[index]=1
            let result=try MainStageProcessing.translate(strip(unsupported))
            assert(result.effects.isEmpty && result.issues.contains{$0.contains("unsupported")})
        }
        var silent=measured;silent[19]=0;silent[20]=0
        let zero=try MainStageProcessing.translate(strip(silent));assert(zero.effects[0].importedDelay?.validate()==true)
        var legacy=ImportedDelay(left:1,right:1,leftSynced:true,rightSynced:true);assert(legacy.validate() && legacy.dryGain==nil)
        legacy.dryGain=1;assert(!legacy.validate(),"Independent levels must be paired")
        assert(MainStagePatch.digest(source)==hash)
        print("PASS: observed Tape Delay note/deviation/manual time, feedback/filters, independent levels, active CC macros, persistence and explicit unsupported-mode rejection")
    }
}
