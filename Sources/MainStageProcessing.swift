import Foundation

/// Data-only decoder: UID references become ordinary dictionaries; archived
/// application classes are never instantiated and MIDI scripts are never run.
enum MainStageProcessing {
    struct Draft:Identifiable {
        var id=UUID()
        var effects:[AudioEffect]=[]
        var macros:[ImportedMacro]=[]
        var issues:[String]=[]
        var low:Int?
        var high:Int?
        var transpose:Int?
        var blockSustain:Bool?
        func appending(to original:ImportedRack?)throws->ImportedRack {
            var rack=original ?? ImportedRack()
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
    static func translate(_ data:Data,channelID:Int?=nil)throws->Draft {
        let devices=try MainStagePatch.devices(data)
        var draft=Draft(),targets:[Int:(effect:Int,name:String)]=[:]
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
            switch device.name {
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
            case "Chorus":
                guard values.count>=3 else{continue}
                effect.kind=5;effect.parameters=[values[2],values[0]/100,0,0,values[1]/100]
                draft.issues.append("Chorus rate, intensity and mix are translated into the native chorus. Its DSP is not Apple's original chorus.")
            default:draft.issues.append("\(device.name): original processing remains archived; no substitute effect was appended.");continue
            }
            guard effect.validate() else{draft.issues.append("\(device.name): parameters outside the native effect's supported range.");continue}
            targets[slot]=(draft.effects.count,device.name);draft.effects.append(effect)
        }
        // Processor bypass flags have not been independently decoded. Preview
        // makes this explicit and never auto-publishes a complete converted patch.
        if !draft.effects.isEmpty {draft.issues.append("Translated processors are enabled in this preview. Original processor bypass flags are not yet decoded; review before applying.")}
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
                  row["rangeIsFlipped"] as? Bool != true,(row["kRangeMappingModeKey"] as? Int ?? 0)==0 else{draft.issues.append("A Smart Control mapping uses an unsupported target, scale or saved-value encoding; its original data remains archived.");continue}
            let parameter:Int,scale:Float
            switch target.name {
            case "Gain":guard sourceParameter==0 else{continue};parameter=0;scale=1
            case "Chan EQ":
                let band=sourceParameter/4,field=sourceParameter%4
                guard band<8,field>0,!(field==2 && (band==0 || band==7)) else{continue}
                parameter=band*3+field-1;scale=1
            case "Chorus":guard (0...2).contains(sourceParameter) else{continue};parameter=[1,4,0][sourceParameter];scale=sourceParameter==2 ? 1:0.01
            default:continue
            }
            guard let descriptor=AudioEffectCatalog.descriptors(for:draft.effects[target.effect].kind).first(where:{$0.index==parameter}),low*scale>=descriptor.minimum,high*scale<=descriptor.maximum else{continue}
            guard abs(draft.effects[target.effect].values[parameter]-Float(saved)*scale)<0.001 else {
                draft.issues.append("A Smart Control saved value does not match the native parameter's units; its mapping was retained as source data rather than guessed.");continue
            }
            let binding=ImportedMacroBinding(effect:target.effect,parameter:parameter,minimum:low*scale,maximum:high*scale)
            if let index=draft.macros.firstIndex(where:{$0.index==owner}) {draft.macros[index].bindings.append(binding)}
            else if (0..<128).contains(owner) {
                var macro=ImportedMacro(index:owner,name:"MainStage Control \(owner+1)",value:Float((saved-Double(low))/Double(high-low))*127,bindings:[binding])
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
