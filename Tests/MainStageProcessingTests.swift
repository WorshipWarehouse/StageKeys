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
        func sampler(_ curves:[Int])->Data {
            var bytes=device("Sampler",[])
            bytes.replaceSubrange(168..<172,with:Data("MELC".utf8))
            for curve in curves {
                var record=Data(repeating:0,count:100)
                record.replaceSubrange(0..<12,with:Data("MELCPMAS1MAS".utf8))
                record.replaceSubrange(12..<21,with:Data("Piano.exs".utf8)+Data([0]))
                for (offset,value) in [(76,0x183),(80,curve)] {
                    let bits=UInt32(bitPattern:Int32(value))
                    for i in 0..<4{record[offset+i]=UInt8((bits >> (i*8)) & 255)}
                }
                bytes.append(record)
            }
            let size=bytes.count-36
            for i in 0..<4{bytes[28+i]=UInt8((size >> (i*8)) & 255)}
            var channel=Data(repeating:0,count:36);channel.replaceSubrange(0..<4,with:Data("OCuA".utf8));channel.append(bytes)
            return channel
        }
        let curveDraft=try MainStageProcessing.translate(sampler([-10,-10]))
        assert(curveDraft.amplitudeVelocityCurve == -10 && curveDraft.hasChanges)
        let curveLayer=try curveDraft.applying(to:Layer(name:"Curve",instrument:-1,gain:1))
        let curveReload=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(curveLayer))
        assert(curveReload.importedRack?.mainStageAmplitudeVelocityCurve == -10)
        assert(curveReload.importedRack?.validate()==true)
        assert(curveReload.midiProgram == nil,"Amplitude response must not alter MIDI/sample-zone velocities")
        assert(curveDraft.issues.contains{$0.contains("requires calibration")})
        for values in [[-10,0],[21],[-21]] {
            do{_ = try MainStageProcessing.translate(sampler(values));assertionFailure("Unsafe curve accepted")}catch{}
        }
        let fullSampler=sampler([-10])
        let bounded=try MainStagePatch.amplitudeVelocityCurve(Data(fullSampler.dropLast(25)),devices:MainStagePatch.devices(fullSampler))
        assert(bounded == nil,"Truncated parameter values must not be read outside their device")
        var wrongFormat=fullSampler;wrongFormat.replaceSubrange(204..<208,with:Data("GAME".utf8))
        let ignored=try MainStagePatch.amplitudeVelocityCurve(wrongFormat,devices:MainStagePatch.devices(wrongFormat))
        assert(ignored == nil,"Effect payloads must not be interpreted as sampler state")
        if let path=ProcessInfo.processInfo.environment["STAGEKEYS_HOST_CURVE_FIXTURE"] {
            let real=try Data(contentsOf:URL(fileURLWithPath:path))
            let curve=try MainStagePatch.amplitudeVelocityCurve(real,devices:MainStagePatch.devices(real))
            assert(curve == -10,"Modern reference channel must retain its observed host curve")
        }
        print("PASS: bounded host curve decoding, duplicate agreement, conflict rejection and channel persistence")
        var source=Data(repeating:0,count:36);source.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        source.append(device("Gain",[-6,0,0,0,0,0,0]))
        var eq:[Float]=[]
        for band in 0..<8{eq += [1,Float([79,198,265,630,1000,1900,4800,11000][band]),band==0 || band==7 ? 3:-2,0.707]}
        source.append(device("Chan EQ",eq));source.append(device("Unmapped",[0,1,2]))
        let row:[String:Any]=["slot":0,"parameterIndex_1":0,"rangeLow":Float(-12),"rangeHigh":Float(0),"kSavedValueDoubleKey":Double(-6),"inputControlEvent":["type":5,"controllerID":71,"channelID":2]]
        let archive=try NSKeyedArchiver.archivedData(withRootObject:["7":[row]],requiringSecureCoding:false)
        for i in 0..<4{source.append(UInt8((archive.count >> (i*8)) & 255))};source.append(archive)
        let translated=try MainStageProcessing.translate(source)
        assert(translated.effects.map(\.kind)==[9,7] && translated.effects[0].values[0] == -6)
        assert(translated.effects[1].values[0]==79 && translated.effects[1].values[6]==265)
        assert(translated.issues.contains{$0.contains("Unmapped")})
        assert(translated.macros.count==1 && translated.macros[0].midiCC==71 && translated.macros[0].midiChannel==2)
        var channelDraft=translated
        channelDraft.low=36;channelDraft.high=96;channelDraft.transpose=12
        MainStageProcessing.channelSettings(["volume":1509949440,"Channel_pan":-0.25,"Channel_isMuted":false,"Channel_filterSustainPedal":true],to:&channelDraft)
        var originalLayer=Layer(name:"Authored patch",instrument:-1,gain:0.5)
        originalLayer.importedRack=ImportedRack(effects:[])
        let applied=try channelDraft.applying(to:originalLayer)
        assert(applied.gain==1 && applied.pan == -0.25 && applied.blockSustain && applied.low==36 && applied.high==96 && applied.transpose==12)
        let item=LibrarySound(id:"mainstage-channel-fixture",name:applied.name,collection:"MainStage Patches",layer:applied)
        let retainedItem=try JSONDecoder().decode(LibrarySound.self,from:JSONEncoder().encode(item))
        assert(retainedItem.layer?.importedRack==applied.importedRack && retainedItem.layer?.gain==1 && retainedItem.layer?.blockSustain==true,"Library persistence must retain authored processing and channel settings")
        var silent=MainStageProcessing.Draft();MainStageProcessing.channelSettings(["volume":0],to:&silent)
        let silentLayer=try silent.applying(to:originalLayer);assert(silentLayer.gain==0,"A source fader at silence must remain silent")
        print("PASS: channel effects/macros, unity/silent faders, pan, sustain, ranges and transpose survive native library persistence")
        var modern=Data(repeating:0,count:36);modern.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        modern.append(device("Channel EQ",eq))
        var modernComp=[Float](repeating:0,count:25)
        modernComp[0] = -18;modernComp[1]=4;modernComp[2]=20;modernComp[3]=150;modernComp[24]=100
        modern.append(device("Compressor",modernComp))
        var bypassed=Data(repeating:0,count:36);bypassed.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        var quietGain=device("Gain",[6,0,0,0,0,0,0]);quietGain[148]=1;bypassed.append(quietGain)
        let bypassDraft=try MainStageProcessing.translate(bypassed)
        assert(bypassDraft.effects.count==1 && !bypassDraft.effects[0].enabled && bypassDraft.effects[0].values[0]==6)
        let bypassLayer=try bypassDraft.applying(to:originalLayer)
        let bypassReloaded=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(bypassLayer))
        assert(bypassReloaded.importedRack?.effects[0].enabled==false)
        quietGain[148]=2;var unknown=Data(repeating:0,count:36);unknown.replaceSubrange(0..<4,with:Data("OCuA".utf8));unknown.append(quietGain)
        let unknownState=try MainStageProcessing.translate(unknown);assert(unknownState.issues.contains{$0.contains("unrecognized processor bypass")})
        let modernFX=try MainStageProcessing.translate(modern)
        assert(modernFX.effects.map(\.kind)==[7,6])
        assert(modernFX.effects[0]==translated.effects[1],"Modern display names must retain the identical EQ parameters")
        let modernLayer=try modernFX.applying(to:originalLayer)
        let reloaded=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(modernLayer))
        assert(reloaded.importedRack==modernLayer.importedRack)
        assert(MainStageProcessing.canonicalName("Stereo Delay")=="St-Delay")
        assert(MainStageProcessing.canonicalName("SilverVerb")=="SilvVerb")
        assert(MainStageProcessing.canonicalName("Clip Distort")=="ClipDist")
        print("PASS: modern MainStage EQ/compressor names retain parameters, order and library state")
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
        delay[11]=8;delay[13]=4;delay[15]=1;delay[16]=2;for i in 17...20{delay[i]=1}
        delay[22]=3300;delay[23]=72;delay[24]=2200;delay[25]=140
        extended.append(device("St-Delay",delay))
        let flipped:[String:Any]=["slot":0,"parameterIndex_1":0,"rangeLow":Float(-60),"rangeHigh":Float(0),"kSavedValueDoubleKey":Double(-38),"rangeIsFlipped":true,"controlName":"Compression","inputControlEvent":["type":5,"controllerID":74,"channelID":0]]
        let extra=try NSKeyedArchiver.archivedData(withRootObject:["2":[flipped]],requiringSecureCoding:false)
        for i in 0..<4{extended.append(UInt8((extra.count >> (i*8)) & 255))};extended.append(extra)
        let next=try MainStageProcessing.translate(extended)
        assert(next.effects.map(\.kind)==[6,3])
        assert(next.effects[0].values==[0,10,370,12,-38,0.75,8.5])
        let stereo=next.effects[1].importedDelay!
        assert(abs(stereo.left-0.565)<0.000001 && stereo.right==0.75 && stereo.leftChannel?.feedback==0.35 && stereo.leftChannel?.crossFeedback==0.3)
        assert(stereo.leftChannel?.lowCut==72 && stereo.rightChannel?.highCut==2200 && stereo.validate())
        var reversed=try next.appending(to:nil)
        assert(reversed.macros[0].name=="Compression")
        assert(reversed.applyMIDI(controller:74,value:0,channel:0) && reversed.effects[0].values[4]==0)
        assert(reversed.applyMIDI(controller:74,value:127,channel:0) && reversed.effects[0].values[4] == -60)
        let roundtrip=try JSONDecoder().decode(ImportedRack.self,from:JSONEncoder().encode(reversed));assert(roundtrip==reversed && roundtrip.validate())
        var synced=Data(repeating:0,count:36);synced.replaceSubrange(0..<4,with:Data("OCuA".utf8));delay[10]=1;synced.append(device("St-Delay",delay))
        let synchronized=try MainStageProcessing.translate(synced);assert(synchronized.effects[0].importedDelay?.left==0.5 && synchronized.effects[0].importedDelay?.right==1 && synchronized.effects[0].importedDelay?.leftSynced==true)
        let syncedDelay=synchronized.effects[0].importedDelay!;assert(syncedDelay.seconds(syncedDelay.left,synced:true,tempo:120)==0.25 && syncedDelay.seconds(syncedDelay.left,synced:true,tempo:60)==0.5)
        var processors=Data(repeating:0,count:36);processors.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        processors.append(device("SilvVerb",[44,17,71,160,6800,760,81,1.2,0.58,0,100,51,1]))
        processors.append(device("ClipDist",[13.5,730,0,28,2000,20000,7,20,0,0]))
        let fx=try MainStageProcessing.translate(processors)
        assert(fx.effects.map(\.kind)==[16,17] && fx.effects.allSatisfy{$0.validate()})
        assert(fx.effects[0].values[0]==17 && fx.effects[0].values[2]==160 && fx.effects[0].values[4]==760 && fx.effects[0].values[3]==0.81)
        assert(fx.effects[0].values[9]==1 && fx.effects[0].values[10]==0.51,"Independent reverb mode must keep 100% dry instead of applying legacy 44% Mix")
        var legacyVerb=Data(repeating:0,count:36);legacyVerb.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        legacyVerb.append(device("SilvVerb",[44,17,71,160,6800,760,81,1.2,0.58,0,100,51,0]))
        let legacyFX=try MainStageProcessing.translate(legacyVerb)
        assert(abs(legacyFX.effects[0].values[9]-0.56)<0.00001 && legacyFX.effects[0].values[10]==0.44)
        var mappedVerb=Data(repeating:0,count:36);mappedVerb.replaceSubrange(0..<4,with:Data("OCuA".utf8));mappedVerb.append(device("SilvVerb",[44,17,71,160,6800,760,81,1.2,0.58,0,100,51,1]))
        let wetRow:[String:Any]=["slot":0,"parameterIndex_1":11,"rangeLow":Float(0),"rangeHigh":Float(100),"kSavedValueDoubleKey":Double(51),"inputControlEvent":["type":5,"controllerID":76,"channelID":0]]
        let wetArchive=try NSKeyedArchiver.archivedData(withRootObject:["4":[wetRow]],requiringSecureCoding:false)
        for i in 0..<4{mappedVerb.append(UInt8((wetArchive.count >> (i*8)) & 255))};mappedVerb.append(wetArchive)
        var mappedRack=try MainStageProcessing.translate(mappedVerb).appending(to:nil)
        assert(mappedRack.applyMIDI(controller:76,value:127,channel:0))
        assert(mappedRack.effects[0].values[9]==1 && mappedRack.effects[0].values[10]==1,"Wet macro must not turn down the independent dry level")
        let reverbSaved=try JSONDecoder().decode(ImportedRack.self,from:JSONEncoder().encode(mappedRack));assert(reverbSaved==mappedRack)
        print("PASS: independent/legacy SilverVerb levels, wet-only MIDI macro and library persistence")
        assert(fx.effects[1].values[0]==13.5 && fx.effects[1].values[3]==0.28 && fx.effects[1].values[6]==7)
        assert(MainStageProcessing.Draft(low:21,high:108,transpose:12).hasChanges)
        print("PASS: native compressor parameters, stereo delay manual times/feedback/filter/mix, reversed CC macros, roundtrip and tempo sync")
        print("PASS: active native MainStage gain/EQ translation, safe keyed-data decoding, linear macro/CC/channel routing, unknown effect retention and append without replacing existing processing")
    }
}
