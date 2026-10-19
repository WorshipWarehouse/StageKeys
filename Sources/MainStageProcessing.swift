import Foundation

/// Data-only decoder: UID references become ordinary dictionaries; archived
/// application classes are never instantiated and MIDI scripts are never run.
enum MainStageProcessing {
    struct Draft:Identifiable {
        var id=UUID()
        var effects:[AudioEffect]=[]
        var sourceNames:[String]=[]
        var macros:[ImportedMacro]=[]
        var issues:[String]=[]
        var low:Int?
        var high:Int?
        var transpose:Int?
        var blockSustain:Bool?
        var gain:Float?
        var pan:Float?
        var muted:Bool?
        var amplitudeVelocityCurve:Int?
        var hasChanges:Bool {amplitudeVelocityCurve != nil || !effects.isEmpty || !macros.isEmpty || low != nil || high != nil || transpose != nil || blockSustain != nil || gain != nil || pan != nil || muted != nil}
        func applying(to original:Layer)throws->Layer {
            var layer=original
            layer.importedRack=try appending(to:layer.importedRack ?? layer.external?.nativeSampler?.rack)
            if let low,let high {layer.low=low;layer.high=high}
            if let transpose {layer.transpose=transpose}
            if let blockSustain {layer.blockSustain=blockSustain}
            if let gain {layer.gain=gain}
            if let pan {layer.pan=pan}
            if let muted {layer.muted=muted}
            return layer
        }
        func appending(to original:ImportedRack?)throws->ImportedRack {
            var rack=original ?? ImportedRack()
            if let amplitudeVelocityCurve {
                guard rack.mainStageAmplitudeVelocityCurve == nil || rack.mainStageAmplitudeVelocityCurve==amplitudeVelocityCurve else{throw MainStagePatch.Failure.invalid("The destination already has a different source velocity curve.")}
                rack.mainStageAmplitudeVelocityCurve=amplitudeVelocityCurve
            }
            let offset=rack.effects.count;rack.effects += effects
            for var macro in macros {
                guard let index=(0..<128).first(where:{candidate in !rack.macros.contains{$0.index==candidate}}) else{throw MainStagePatch.Failure.invalid("No free macro slots.")}
                macro.index=index
                for binding in macro.bindings.indices {macro.bindings[binding].effect += offset}
                rack.macros.append(macro)
            }
            guard rack.validate() else{throw MainStagePatch.Failure.invalid("Combined processing exceeds the native rack limits.")}
            return rack
        }
    }
    static func channelSettings(_ source:[String:Any],to draft:inout Draft) {
        draft.blockSustain=source["Channel_filterSustainPedal"] as? Bool
        draft.muted=source["Channel_isMuted"] as? Bool
        if let pan=source["Channel_pan"] as? NSNumber,pan.floatValue.isFinite,(-1...1).contains(pan.floatValue) {draft.pan=pan.floatValue}
        if let volume=source["volume"] as? NSNumber {
            if volume.int64Value==0 {draft.gain=0}
            else if volume.int64Value==1509949440 {draft.gain=1}
        }
        if let volume=source["volume"] as? NSNumber,![Int64(0),1509949440].contains(volume.int64Value) {
            draft.issues.append("The source channel fader is retained in the archived patch; its non-unity taper requires calibration. Native import uses unity gain instead of adding the previous automatic −6 dB attenuation.")
        }
        if let expression=source["Channel_expressionValue"] as? Int,expression != 127 {draft.issues.append("Source expression \(expression) is retained; channel expression response requires translation.")}
        if let sends=source["Channel_sends"] as? [[String:Any]],sends.contains(where:{!$0.isEmpty}) {draft.issues.append("Source bus sends are retained in the patch archive; auxiliary routing is not flattened into insert effects.")}
    }
    static func archives(_ data:Data)throws->[[String:Any]] {
        var result:[[String:Any]]=[],position=0
        while position<data.count,let range=data.range(of:Data("bplist00".utf8),in:position..<data.count) {
            let start=range.lowerBound;position=range.upperBound
            guard start>=4 else{continue}
            let size=(0..<4).reduce(0){$0 | Int(data[start-4+$1]) << ($1*8)}
            guard size>=40,size<=data.count-start,size<=4_000_000,result.count<64 else{continue}
            guard let encoded=try? PropertyListSerialization.propertyList(from:data.subdata(in:start..<start+size),options:[],format:nil) as? [String:Any],encoded["$archiver"] as? String == "NSKeyedArchiver" else{continue}
            let xml=try PropertyListSerialization.data(fromPropertyList:encoded,format:.xml,options:0)
            guard let text=String(data:xml,encoding:.utf8),let normalized=text.replacingOccurrences(of:"CF$UID",with:"StageKeysUID").data(using:.utf8),
                  let raw=try PropertyListSerialization.propertyList(from:normalized,options:[],format:nil) as? [String:Any],let objects=raw["$objects"] as? [Any],objects.count<=16384 else{continue}
            var visits=0
            func resolve(_ value:Any,_ depth:Int=0)throws->Any {
                visits+=1;guard visits<=100000,depth<=32 else{throw MainStagePatch.Failure.invalid("Archived mapping recursion exceeds limits.")}
                if let dictionary=value as? [String:Any] {
                    if let index=dictionary["StageKeysUID"] as? Int {
                        guard objects.indices.contains(index) else{throw MainStagePatch.Failure.invalid("Invalid archived mapping reference.")}
                        return try resolve(objects[index],depth+1)
                    }
                    if let keys=dictionary["NS.keys"] as? [Any],let values=dictionary["NS.objects"] as? [Any] {
                        guard keys.count==values.count else{throw MainStagePatch.Failure.invalid("Invalid archived dictionary.")}
                        var mapped:[String:Any]=[:]
                        for (key,val) in zip(keys,values){mapped[String(describing:try resolve(key,depth+1))]=try resolve(val,depth+1)}
                        return mapped
                    }
                    if let values=dictionary["NS.objects"] as? [Any] {return try values.map{try resolve($0,depth+1)}}
                    var mapped:[String:Any]=[:]
                    for (key,val) in dictionary where key != "$class" {mapped[key]=try resolve(val,depth+1)}
                    return mapped
                }
                if let values=value as? [Any] {return try values.map{try resolve($0,depth+1)}}
                return value
            }
            if let root=try resolve(raw["$top"] ?? [:]) as? [String:Any] {result.append(root)}
        }
        return result
    }
    // Newer channel strips retain longer display names in the same parameter records.
    static func canonicalName(_ name:String)->String {
        switch name {
        case "Channel EQ":return "Chan EQ"
        case "Compressor":return "Comp"
        case "Stereo Delay":return "St-Delay"
        case "SilverVerb", "Silver Verb":return "SilvVerb"
        case "Clip Distort", "Clip Distortion":return "ClipDist"
        default:return name
        }
    }
    static func translate(_ data:Data,channelID:Int?=nil)throws->Draft {
        let devices=try MainStagePatch.devices(data)
        var draft=Draft(),targets:[Int:(effect:Int,name:String)]=[:]
        draft.amplitudeVelocityCurve=try MainStagePatch.amplitudeVelocityCurve(data,devices:devices)
        if let curve=draft.amplitudeVelocityCurve,curve != 0 {
            draft.issues.append("Sampler amplitude velocity curve \(curve) is preserved per channel. Its host response still requires calibration; MIDI velocity, sample selection and filter response are not remapped.")
        }
        var independentReverbSlots=Set<Int>()
        for (slot,device) in devices.enumerated() {
            let end=min(data.count,device.offset+device.byteCount)
            guard let range=data.range(of:Data("GAMETSPP".utf8),in:device.offset..<end),range.upperBound+8<=end else {
                draft.issues.append("\(device.name): no supported native effect parameter record.");continue
            }
            let start=range.upperBound+8
            var values:[Float]=[]
            for i in stride(from:start,to:end-3,by:4) {
                let bits=(0..<4).reduce(UInt32(0)){$0 | UInt32(data[i+$1]) << ($1*8)}
                values.append(Float(bitPattern:bits))
            }
            var effect=AudioEffect()
            let nativeName=canonicalName(device.name)
            switch nativeName {
            case "Chan EQ":
                guard values.count>=32 else{draft.issues.append("Truncated Channel EQ parameters.");continue}
                effect.kind=7;var parameters=AudioEffectCatalog.defaults(for:7)
                for band in 0..<8 {
                    let source=band*4,destination=band*3,on=values[source] != 0
                    parameters[destination]=on ? values[source+1] : band==0 ? 20:band==7 ? 20000:values[source+1]
                    if band != 0 && band != 7 {parameters[destination+1]=on ? values[source+2]:0}
                    parameters[destination+2]=values[source+3]
                }
                effect.parameters=parameters
                draft.issues.append("Channel EQ frequencies, gains, Q and band bypass values are translated. Filter slopes, output gain and exact Apple EQ response remain approximate/unmapped.")
            case "Gain":
                guard values.count>=7,values[1..<7].allSatisfy({$0==0}) else{draft.issues.append("Gain polarity/stereo options require translation.");continue}
                effect.kind=9;effect.parameters=[values[0]]
            case "Comp":
                guard values.count>=25 else{draft.issues.append("Truncated Compressor parameters.");continue}
                effect.kind=6;effect.parameters=[0,values[2],values[3],values[1],values[0],values[24]/100,values[4]]
                draft.issues.append("Compressor threshold, ratio, attack, release, manual makeup and mix are translated. Circuit model, knee, automatic gain/release, sidechain and limiter behavior are not identical to Apple's compressor; review the native response.")
            case "St-Delay":
                guard values.count>=26 else{draft.issues.append("Truncated Stereo Delay parameters.");continue}
                guard [values[15],values[16]].allSatisfy({$0.isFinite && (0...4).contains($0) && $0.rounded()==$0}),[0,1].contains(values[10]),[1,-1].contains(values[17]),[1,-1].contains(values[18]),[1,-1].contains(values[19]),[1,-1].contains(values[20]),values[21]==0 else{draft.issues.append("Stereo Delay has unsupported sync/phase/tempo-freeze state.");continue}
                let synced=values[10]==1
                guard !synced || (values[11]>0 && values[13]>0 && (-99...100).contains(values[12]) && (-99...100).contains(values[14])) else{draft.issues.append("Invalid Stereo Delay note/deviation values.");continue}
                let left=synced ? 4/Double(values[11])*(1+Double(values[12])/100):Double(values[2])/1000
                let right=synced ? 4/Double(values[13])*(1+Double(values[14])/100):Double(values[3])/1000
                var delay=ImportedDelay(left:left,right:right,leftSynced:synced,rightSynced:synced)
                // Apple's parameter-order metadata: 6 is L→R, 7 is R→L.
                delay.leftChannel = .init(feedback:values[4]/100,crossFeedback:values[7]/100,mix:values[0]/100,input:Int(values[15]),feedbackPolarity:values[17],crossPolarity:values[20],lowCut:max(20,values[23]),highCut:min(20000,values[22]))
                delay.rightChannel = .init(feedback:values[5]/100,crossFeedback:values[6]/100,mix:values[1]/100,input:Int(values[16]),feedbackPolarity:values[18],crossPolarity:values[19],lowCut:max(20,values[25]),highCut:min(20000,values[24]))
                guard delay.validate() else{draft.issues.append("Stereo Delay feedback/filter values exceed the stable native range.");continue}
                effect.kind=3;effect.importedDelay=delay;effect.parameters=[0,1,20000,1]
                draft.issues.append("Stereo Delay note sync, percentage deviation, input routing, feedback/crossfeed polarity, mix and channel filters are translated. Delay changes are immediate; original smoothing, freeze mode and exact filter/sum response are not identical.")
            case "SilvVerb":
                guard values.count>=10 else{draft.issues.append("Truncated SilverVerb parameters.");continue}
                var dry=1-values[0]/100,wet=values[0]/100
                if values.count>=13 {
                    guard values[12]==0 || values[12]==1 else{draft.issues.append("SilverVerb has an unknown Dry/Wet mode; original processing remains archived.");continue}
                    if values[12]==1 {
                        guard values[10].isFinite,values[11].isFinite,(0...100).contains(values[10]),(0...100).contains(values[11]) else{draft.issues.append("SilverVerb has invalid independent Dry/Wet levels.");continue}
                        dry=values[10]/100;wet=values[11]/100;independentReverbSlots.insert(slot)
                    }
                }
                effect.kind=16;effect.parameters=[values[1],values[2]/100,values[3],values[6]/100,values[5],values[4],values[7],values[8],values[9],dry,wet]
                draft.issues.append("SilverVerb predelay, modulation, filters and active legacy Mix or independent Dry/Wet levels are translated. The independent native reverb does not reproduce Apple's proprietary decay/density circuit exactly.")
            case "ClipDist":
                guard values.count>=10 else{draft.issues.append("Truncated Clip Distortion parameters.");continue}
                effect.kind=17;effect.parameters=Array(values.prefix(10));effect.parameters![3]/=100
                draft.issues.append("Clip Distortion drive, tone, symmetry, mix, clip/sum filters, shelf and input/output gains are translated. The native nonlinear curve is independent and does not claim Apple's exact harmonic spectrum.")
            case "Chorus":
                guard values.count>=3 else{continue}
                effect.kind=5;effect.parameters=[values[2],values[0]/100,0,0,values[1]/100]
                draft.issues.append("Chorus rate, intensity and mix are translated into the native chorus. Its DSP is not Apple's original chorus.")
            default:draft.issues.append("\(device.name): original processing remains archived; no substitute effect was appended.");continue
            }
            // Paired MainStage exports differ at this UInt32 only when host bypass changes.
            // Keep the ordered slot, including bypassed effects, so macro indices stay stable.
            if device.offset+152<=end {
                let flag=(0..<4).reduce(UInt32(0)){$0 | UInt32(data[device.offset+148+$1]) << ($1*8)}
                if flag<=1 {effect.enabled=flag==0}
                else {draft.issues.append("\(device.name): unrecognized processor bypass flag; review its enabled state.")}
            }
            guard effect.validate() else{draft.issues.append("\(device.name): parameters outside the native effect's supported range.");continue}
            targets[slot]=(draft.effects.count,nativeName);draft.effects.append(effect);draft.sourceNames.append(device.name)
        }
        let decoded=try archives(data)
        var rows:[(Int,[String:Any])]=[]
        func visit(_ object:Any,_ owner:Int=0) {
            if let dictionary=object as? [String:Any] {
                if dictionary["slot"] != nil,dictionary["parameterIndex_1"] != nil {rows.append((owner,dictionary))}
                if let low=dictionary["lowNote"] as? Int,let high=dictionary["highNote"] as? Int,(0...127).contains(low),(low...127).contains(high) {
                    draft.low=low;draft.high=high
                    if let transpose=dictionary["transpose"] as? Int,(-48...48).contains(transpose){draft.transpose=transpose}
                }
                for (key,val) in dictionary {visit(val,Int(key) ?? owner)}
            }else if let values=object as? [Any] {for value in values{visit(value,owner)}}
        }
        for object in decoded {visit(object)}
        for (owner,row) in rows.prefix(128) {
            if let channelID,let targetChannel=row["kGInstIDKey"] as? Int,targetChannel != channelID {continue}
            guard let slot=row["slot"] as? Int,let target=targets[slot],let sourceParameter=row["parameterIndex_1"] as? Int,
                  let low=row["rangeLow"] as? Float,let high=row["rangeHigh"] as? Float,low<high,
                  let saved=row["kSavedValueDoubleKey"] as? Double,saved.isFinite,Double(low)<=saved,saved<=Double(high),
                  (row["kRangeMappingModeKey"] as? Int ?? 0)==0 else{draft.issues.append("A Smart Control mapping uses an unsupported target, scale or saved-value encoding; its original data remains archived.");continue}
            let parameter:Int,scale:Float
            switch target.name {
            case "Gain":guard sourceParameter==0 else{continue};parameter=0;scale=1
            case "Chan EQ":
                let band=sourceParameter/4,field=sourceParameter%4
                guard band<8,field>0,!(field==2 && (band==0 || band==7)) else{continue}
                parameter=band*3+field-1;scale=1
            case "Comp":
                let mapping:[Int:(Int,Float)]=[0:(4,1),1:(3,1),2:(1,1),3:(2,1),4:(6,1),24:(5,0.01)]
                guard let mapped=mapping[sourceParameter] else{continue};parameter=mapped.0;scale=mapped.1
            case "SilvVerb":
                let independent=independentReverbSlots.contains(slot)
                guard independent ? sourceParameter != 0 : ![10,11].contains(sourceParameter) else{draft.issues.append("A SilverVerb macro targets an inactive mix mode; its mapping remains archived.");continue}
                let mapping:[Int:(Int,Float)]=[0:(10,0.01),1:(0,1),2:(1,0.01),3:(2,1),6:(3,0.01),5:(4,1),4:(5,1),7:(6,1),8:(7,1),9:(8,1),10:(9,0.01),11:(10,0.01)]
                guard let mapped=mapping[sourceParameter] else{continue};parameter=mapped.0;scale=mapped.1
            case "ClipDist":guard (0..<10).contains(sourceParameter) else{continue};parameter=sourceParameter;scale=sourceParameter==3 ? 0.01:1
            case "Chorus":guard (0...2).contains(sourceParameter) else{continue};parameter=[1,4,0][sourceParameter];scale=sourceParameter==2 ? 1:0.01
            default:continue
            }
            guard let descriptor=AudioEffectCatalog.descriptors(for:draft.effects[target.effect].kind).first(where:{$0.index==parameter}),low*scale>=descriptor.minimum,high*scale<=descriptor.maximum else{continue}
            guard abs(draft.effects[target.effect].values[parameter]-Float(saved)*scale)<0.001 else {
                draft.issues.append("A Smart Control saved value does not match the native parameter's units; its mapping was retained as source data rather than guessed.");continue
            }
            let flipped=row["rangeIsFlipped"] as? Bool == true
            let binding=ImportedMacroBinding(effect:target.effect,parameter:parameter,minimum:(flipped ? high:low)*scale,maximum:(flipped ? low:high)*scale)
            var bindings=[binding]
            if target.name=="SilvVerb" && sourceParameter==0 {bindings.append(ImportedMacroBinding(effect:target.effect,parameter:9,minimum:1-binding.minimum,maximum:1-binding.maximum))}
            let fraction=Float((saved-Double(low))/Double(high-low))
            let normalized=(flipped ? 1-fraction:fraction)*127
            if let index=draft.macros.firstIndex(where:{$0.index==owner}) {
                guard abs(draft.macros[index].value-normalized)<0.05 else{draft.issues.append("A Smart Control has conflicting saved positions; the conflicting mapping remains archived.");continue}
                draft.macros[index].bindings.append(contentsOf:bindings)
            }
            else if (0..<128).contains(owner) {
                var macro=ImportedMacro(index:owner,name:(row["controlName"] as? String ?? "MainStage Control \(owner+1)"),value:normalized,bindings:bindings)
                if let event=row["inputControlEvent"] as? [String:Any],event["type"] as? Int==5,let cc=event["controllerID"] as? Int,(0...127).contains(cc) {
                    macro.midiCC=cc
                    if let channel=event["channelID"] as? Int,(0...15).contains(channel){macro.midiChannel=channel}
                }
                draft.macros.append(macro)
            }
        }
        return draft
    }
}
