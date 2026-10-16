import Foundation
import AVFoundation

struct NativeSamplerProgram:Codable,Hashable {
    struct Group:Codable,Hashable {
        var name:String
        var layer:Int
        var low:Int
        var high:Int
        var velocityLow:Int
        var velocityHigh:Int
        var controller:Int?
        var controllerLow:Int=0
        var controllerHigh:Int=127
        var enabled:Bool=true
    }
    var groups:[Group]
    var notes:[String]
    var compactGroups:Bool?
    var conversionVersion:Int?
    var amplitudeEnvelope:EXSNative.Envelope?
    var valid:Bool {
        (conversionVersion.map{(1...2).contains($0)} ?? true) && (amplitudeEnvelope?.valid ?? true) && !groups.isEmpty && groups.count<=64 && notes.count<=32 && notes.allSatisfy{$0.count<=2000} && groups.allSatisfy {group in
            group.name.count<=200 && (0..<64).contains(group.layer) && (0...127).contains(group.low) && (group.low...127).contains(group.high) && (0...127).contains(group.velocityLow) && (group.velocityLow...127).contains(group.velocityHigh) && (group.controller.map{(0...127).contains($0)} ?? true) && (0...127).contains(group.controllerLow) && (group.controllerLow...127).contains(group.controllerHigh)
        } && rack.validate()
    }
    var rack:ImportedRack {
        if compactGroups==true {
            // Key/velocity rules are baked into each native zone. Share one
            // sampler per controller bank instead of loading one per EXS group.
            let banks=Dictionary(grouping:groups){group in "\(group.controller ?? -1):\(group.controllerLow):\(group.controllerHigh):\(group.enabled)"}
            let branches=banks.keys.sorted().map {key -> ImportedBranch in
                let bank=banks[key]!,first=bank[0]
                var branch=ImportedBranch(name:first.controller.map{"CC\($0) · \(first.controllerLow)–\(first.controllerHigh)"} ?? "Instrument Layers",sampleLayers:bank.map(\.layer).sorted(),rack:ImportedRack(),enabled:first.enabled)
                if let controller=first.controller {branch.controllerGate=SamplerControllerGate(controller:controller,low:first.controllerLow,high:first.controllerHigh)}
                return branch
            }
            return ImportedRack(branches:branches)
        }
        return ImportedRack(branches:groups.map {group in
            var branch=ImportedBranch(name:group.name,sampleLayers:[group.layer],rack:ImportedRack(),low:group.low,high:group.high,velocityLow:max(1,group.velocityLow),velocityHigh:group.velocityHigh,enabled:group.enabled)
            if let controller=group.controller {branch.controllerGate=SamplerControllerGate(controller:controller,low:group.controllerLow,high:group.controllerHigh)}
            return branch
        })
    }
}
struct SamplerControllerGate:Codable,Equatable {
    var controller:Int
    var low:Int
    var high:Int
    var valid:Bool {(0...127).contains(controller) && (0...127).contains(low) && (low...127).contains(high)}
    func accepts(_ values:[Int:Int])->Bool {(low...high).contains(values[controller] ?? ([7,11].contains(controller) ? 127:0))}
}

/// Independent bounded EXS-to-native-map translation. Original audio is referenced,
/// never rendered, sliced into new recordings, normalized or sample-rate converted.
/// Zone/sample field layout informed by Matt Allan's MIT EXS parser (see Licenses).
enum EXSNative {
    struct Envelope:Codable,Hashable {
        var attack:Double
        var lowVelocityAttack:Double
        var decay:Double
        var sustain:Double
        var release:Double
        var valid:Bool {[attack,lowVelocityAttack,decay,release].allSatisfy{$0.isFinite && (0...10).contains($0)} && sustain.isFinite && (0...1).contains(sustain)}
        // EXS control values use a fourth-power time curve, not milliseconds.
        static func seconds(_ value:Int)->Double {10*pow(Double(value)/127,4)}
    }
    /// Decode parameter IDs and signed values as data, never executable state.
    static func parameters(_ body:[UInt8])throws->[Int:Int] {
        func u16(_ i:Int)->Int {Int(body[i]) | Int(body[i+1]) << 8}
        func u32(_ i:Int)->Int {u16(i) | u16(i+2) << 16}
        guard body.count>=4 else{throw MainStagePatch.Failure.invalid("Truncated EXS parameters.")}
        let count=u32(0)
        guard count<=512,4+count*3<=body.count else{throw MainStagePatch.Failure.invalid("Invalid EXS parameter count.")}
        var values:[Int:Int]=[:]
        for i in 0..<count where body[4+i] != 0 {
            let id=Int(body[4+i]);guard values[id]==nil else{throw MainStagePatch.Failure.invalid("Duplicate EXS parameter ID.")}
            values[id]=Int(Int16(bitPattern:UInt16(u16(4+count+i*2))))
        }
        let end=4+count*3
        if body.count>end {
            guard body.count>=end+4 else{throw MainStagePatch.Failure.invalid("Truncated extended EXS parameters.")}
            let extra=u32(end)
            guard extra<=512,end+4+extra*4<=body.count else{throw MainStagePatch.Failure.invalid("Invalid extended EXS parameters.")}
            for i in 0..<extra {
                let pos=end+4+i*4,id=u16(pos)
                if id != 0 {values[id]=Int(Int16(bitPattern:UInt16(u16(pos+2))))}
            }
        }
        return values
    }
    static func envelope(_ parts:[Chunk])throws->Envelope? {
        guard let chunk=parts.first(where:{$0.kind==4}) else{return nil}
        let values=try parameters(chunk.body)
        guard [0x52,0x53,0x54,0x51,0x55].allSatisfy({values[$0].map{(0...127).contains($0)} ?? false}) else{return nil}
        // Modern alternative envelope shapes need separate translation.
        guard values[0x6b]==nil || values[0x6b]==2 else{return nil}
        return Envelope(attack:Envelope.seconds(values[0x52]!),lowVelocityAttack:Envelope.seconds(values[0x53]!),decay:Envelope.seconds(values[0x54]!),sustain:Double(values[0x51]!)/127,release:Envelope.seconds(values[0x55]!))
    }
    static func applyEnvelope(_ envelope:Envelope?,group:[UInt8],to layer:inout [String:Any]) {
        func offset(_ pos:Int)->Double {Double((0..<4).reduce(0){$0 | Int(group[pos+$1]) << ($1*8)})/1000}
        guard var envelopes=layer["Envelopes"] as? [[String:Any]],!envelopes.isEmpty,var stages=envelopes[0]["Stages"] as? [[String:Any]] else{return}
        for i in stages.indices {
            switch stages[i]["stage"] as? Int {
            case 1:stages[i]["time"]=max(0.001,(envelope?.attack ?? 0.001)+offset(56))
            case 3:stages[i]["time"]=max(0.001,(envelope?.decay ?? 0.001)+offset(60))
            case 4:stages[i]["level"]=min(1,max(0,(envelope?.sustain ?? 1)+offset(64)))
            case 5:stages[i]["time"]=max(0.001,(envelope?.release ?? 0.1)+offset(68))
            default:break
            }
        }
        envelopes[0]["Stages"]=stages;layer["Envelopes"]=envelopes
    }

    struct Chunk {var kind:Int;var modern:Bool;var index:Int;var name:String;var body:[UInt8]}
    static func chunks(_ data:Data)throws->[Chunk] {
        guard data.count>=84,data.count<=16_000_000 else{throw MainStagePatch.Failure.invalid("Invalid EXS document size.")}
        let bytes=[UInt8](data)
        let big=Array(bytes[16..<20])==Array("SOBT".utf8) || Array(bytes[16..<20])==Array("SOBJ".utf8)
        func u32(_ position:Int)->Int {(0..<4).reduce(0){$0 | Int(bytes[position+$1]) << ((big ? 3-$1:$1)*8)}}
        var offset=0,result:[Chunk]=[]
        while offset<bytes.count {
            guard offset+84<=bytes.count else{throw MainStagePatch.Failure.invalid("Truncated EXS chunk.")}
            let signature=u32(offset),size=u32(offset+4),tag=String(bytes:bytes[offset+16..<offset+20],encoding:.ascii)
            guard ["TBOS","JBOS","SOBT","SOBJ"].contains(tag ?? ""),signature & 0x00ffffff == 0x101,size<=bytes.count-offset-84,result.count<16384 else{throw MainStagePatch.Failure.invalid("Unsupported EXS chunk layout.")}
            guard !big else{throw MainStagePatch.Failure.invalid("Native EXS translation currently requires little-endian documents.")}
            let name=String(bytes:bytes[offset+20..<offset+84].prefix(while:{$0 != 0}),encoding:.utf8) ?? "EXS Object"
            result.append(Chunk(kind:(signature >> 24) & 0x3f,modern:signature & 0x40000000 != 0,index:u32(offset+8),name:name,body:Array(bytes[offset+84..<offset+84+size])))
            offset+=84+size
        }
        return result
    }
    static func convert(_ source:URL,sampleRoot:URL,to output:URL)throws->NativeSamplerProgram {
        precondition(Thread.isMainThread)
        let attributes=try source.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard attributes.isRegularFile==true,(attributes.fileSize ?? Int.max)<=16_000_000 else{throw MainStagePatch.Failure.invalid("Invalid EXS document size.")}
        let parts=try chunks(Data(contentsOf:source)),groups=parts.filter{$0.kind==2},sampleParts=parts.filter{$0.kind==3},zones=parts.filter{$0.kind==1}
        guard !sampleParts.isEmpty,sampleParts.count<=4096,!zones.isEmpty,zones.count<=16384,groups.count<=64 else{throw MainStagePatch.Failure.invalid("EXS map exceeds native limits or is empty.")}
        func u32(_ bytes:[UInt8],_ position:Int)->Int {(0..<4).reduce(0){$0 | Int(bytes[position+$1]) << ($1*8)}}
        func signed(_ byte:UInt8)->Int {Int(Int8(bitPattern:byte))}
        func string(_ bytes:[UInt8],_ position:Int,_ length:Int)throws->String {
            guard position+length<=bytes.count,let value=String(bytes:bytes[position..<position+length].prefix(while:{$0 != 0}),encoding:.utf8) else{throw MainStagePatch.Failure.invalid("Invalid EXS sample path.")};return value
        }
        let root=sampleRoot.resolvingSymlinksInPath().standardizedFileURL
        var files:[Int:URL]=[:],frames:[Int:Int]=[:],references:[String:String]=[:]
        guard Set(sampleParts.map(\.index)).count==sampleParts.count,sampleParts.allSatisfy({(0..<4096).contains($0.index)}) else{throw MainStagePatch.Failure.invalid("Invalid or duplicate EXS sample IDs.")}
        for sample in sampleParts {
            guard sample.body.count>=592 else{throw MainStagePatch.Failure.invalid("Unsupported EXS sample record.")}
            let directory=try string(sample.body,80,256)
            let name=try string(sample.body,336,256)
            guard !name.isEmpty,name==URL(fileURLWithPath:name).lastPathComponent else{throw MainStagePatch.Failure.invalid("Unsafe EXS sample filename.")}
            let original=URL(fileURLWithPath:directory,isDirectory:true).appendingPathComponent(name)
            let pathParts=original.pathComponents.filter{$0 != "/" && $0 != "." && $0 != ".."}
            let candidates=[original]+(1...min(16,pathParts.count)).map{root.appendingPathComponent(pathParts.suffix($0).joined(separator:"/"))}
            guard let file=candidates.map({$0.resolvingSymlinksInPath().standardizedFileURL}).first(where:{$0.path.hasPrefix(root.path+"/") && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}) else{throw MainStagePatch.Failure.invalid("Missing original EXS sample: \(name). Choose its sample folder.")}
            let audio=try AVAudioFile(forReading:file)
            guard audio.length>0,audio.length<=Int64(Int32.max) else{throw MainStagePatch.Failure.invalid("Unsupported EXS sample length.")}
            files[sample.index]=file;frames[sample.index]=Int(audio.length);references["Sample:\(0x10000000+sample.index)"]=file.path
        }
        guard let first=files.values.first else{throw MainStagePatch.Failure.invalid("Missing EXS audio.")}
        let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[first])
        guard var state=sampler.auAudioUnit.fullStateForDocument,var instrument=state["Instrument"] as? [String:Any],let template=(instrument["Layers"] as? [[String:Any]])?.first else{throw MainStagePatch.Failure.invalid("Cannot initialize StageKeys Sampler.")}
        var native:[[String:Any]]=[],rules:[NativeSamplerProgram.Group]=[]
        var notes=Set<String>()
        let amplitude=try envelope(parts)
        if amplitude != nil {
            notes.insert("EXS amplitude attack, decay, sustain and release are translated using the source time curve. Velocity-dependent attack, envelope shape and group offset interaction remain approximate; global filter/modulation remain unmapped.")
        } else if parts.contains(where:{$0.kind==4}) {notes.insert("Original EXS global parameter data is retained. The amplitude envelope layout is unsupported; a fallback envelope is used. Global filter/modulation remain unmapped.")}
        let ungrouped=zones.contains{$0.body.count>=92 && u32($0.body,88)==0xffffffff}
        var activeGroups=groups
        if groups.isEmpty || ungrouped {
            guard activeGroups.count<64 else{throw MainStagePatch.Failure.invalid("Too many EXS groups including ungrouped zones.")}
            activeGroups.append(Chunk(kind:2,modern:false,index:0xffffffff,name:"Instrument",body:Array(repeating:0,count:120)))
        }
        for group in activeGroups {
            let b=group.body
            guard b.count>=92 else{throw MainStagePatch.Failure.invalid("Unsupported EXS group record.")}
            let kind=Int(b[84])
            guard kind==0 || kind==3,b[73]==0,b[2]==0,b[4]==0,b[7]==0,b[3]&0xee==0,u32(b,80)==0xffffffff || u32(b,80)==0,
                  b[32]==0,b[35]==0 else{throw MainStagePatch.Failure.invalid("EXS group \(group.name) uses unsupported round-robin, release-trigger, crossfade or selection behavior. No flattened replacement was created.")}
            guard b[1]==0 else{throw MainStagePatch.Failure.invalid("EXS group pan requires verified native translation.")}
            let groupLow=b[3]&1 != 0 ? Int(b[88]):0,groupHigh=b[3]&1 != 0 ? Int(b[89]):127
            let groupVelocityLow=Int(b[5]),groupVelocityHigh=group.index==0xffffffff ? 127:Int(b[6])
            guard (0...127).contains(groupLow),(groupLow...127).contains(groupHigh),(0...127).contains(groupVelocityLow),(groupVelocityLow...127).contains(groupVelocityHigh) else{throw MainStagePatch.Failure.invalid("Invalid EXS group ranges.")}
            var mapped:[[String:Any]]=[]
            for zone in zones {
                let z=zone.body
                guard z.count>=96 else{throw MainStagePatch.Failure.invalid("Truncated EXS zone.")}
                guard u32(z,88)==group.index else{continue}
                let sample=u32(z,92)
                guard let length=frames[sample] else{throw MainStagePatch.Failure.invalid("An EXS zone references an unknown sample.")}
                guard z[0] & 0x47 == 0,z[5]==0,z[34]==0,u32(z,28)==0,z[32]==0 else{throw MainStagePatch.Failure.invalid("EXS zone \(zone.name) uses unsupported reverse, one-shot, unpitched, loop crossfade/tuning or output routing.")}
                let start=u32(z,12)
                var end=u32(z,16),loopStart=u32(z,20),loopEnd=u32(z,24)
                let looped=z[33] & 1 != 0
                if looped && loopEnd>end {
                    end=loopEnd
                    notes.insert("Consolidated attack and loop-tail extents are combined into a continuous native region. Source split-region transition behavior is not yet verified identical.")
                }
                if end>=length || looped && loopEnd>=length {
                    end=min(end,length-1);loopEnd=min(loopEnd,length-1)
                    notes.insert("Some saved EXS endpoints exceed the original audio length. Native endpoints are bounded to the original file; unmodified source values remain in the retained EXS.")
                }
                guard start>=0,end>start,end<length else{throw MainStagePatch.Failure.invalid("Invalid EXS sample-region bounds.")}
                guard !looped || (loopStart>=start && loopEnd>loopStart && loopEnd<=end) else{throw MainStagePatch.Failure.invalid("EXS loop leaves its consolidated sample region.")}
                if z[33] & 4 != 0 {throw MainStagePatch.Failure.invalid("EXS loop release-to-end needs native translation.")}
                guard z[1]<=127,z[6]<=z[7],z[7]<=127,z[9]<=127,z[10]<=127,(-64...64).contains(signed(z[3])) else{throw MainStagePatch.Failure.invalid("Invalid EXS zone ranges or pan.")}
                let low=max(Int(z[6]),groupLow),high=min(Int(z[7]),groupHigh)
                let velocityLow=max(z[0]&8 != 0 ? Int(z[9]):0,groupVelocityLow),velocityHigh=min(z[0]&8 != 0 ? Int(z[10]):127,groupVelocityHigh)
                if low>high || velocityLow>velocityHigh {continue}
                var item:[String:Any]=["ID":mapped.count,"name":zone.name,"enabled":true,"waveform":0x10000000+sample,"min key":low,"max key":high,"root key":Int(z[1]),"min vel":velocityLow,"max vel":velocityHigh,"gain":signed(z[4]),"fine tune":signed(z[2])+(z.count>80 ? signed(z[80])*100:0),"pan":Double(signed(z[3]))/64,"sample start":start,"sample end":end,"loop enabled":looped]
                if looped {item["loop start"]=loopStart;item["loop end"]=loopEnd}
                mapped.append(item)
            }
            if mapped.isEmpty {continue}
            let index=native.count,layerID=template["ID"] as? Int ?? 0
            var layer=template;layer["ID"]=index;layer["name"]=group.name;layer["Zones"]=mapped
            layer["gain"]=signed(b[0]);layer["pan"]=Double(signed(b[1]))/64
            layer["min vel"]=Int(b[5]);layer["max vel"]=group.index==0xffffffff ? 127:Int(b[6])
            layer["Filters"]=["ID":0,"enabled":false,"cutoff":20000.0,"resonance":0.0]
            if var lfos=layer["LFOs"] as? [[String:Any]] {for i in lfos.indices{lfos[i]["enabled"]=false};layer["LFOs"]=lfos}
            if var connections=layer["Connections"] as? [[String:Any]] {
                connections.removeAll{($0["source"] as? Int)==268435456 && ($0["destination"] as? Int)==816840704}
                for i in connections.indices {for key in ["source","destination","control"] {if let value=connections[i][key] as? Int,value>=0x10000000 {connections[i][key]=value+(index-layerID)*256}}}
                layer["Connections"]=connections
            }
            guard [56,60,64].allSatisfy({u32(b,$0)==0}),u32(b,68)<=30000 else{throw MainStagePatch.Failure.invalid("EXS group envelope offsets require further translation.")}
            applyEnvelope(amplitude,group:b,to:&layer)
            if [56,60,64,68].contains(where:{u32(b,$0)>0}) {notes.insert("EXS group release offsets are applied to the native envelope. Their interaction with the original global envelope remains approximate.")}
            let keyRange=b[3]&1 != 0
            let rule=NativeSamplerProgram.Group(name:group.name,layer:index,low:keyRange ? Int(b[88]):0,high:keyRange ? Int(b[89]):127,velocityLow:Int(b[5]),velocityHigh:group.index==0xffffffff ? 127:Int(b[6]),controller:kind==3 ? Int(b[85]):nil,controllerLow:Int(b[86]),controllerHigh:Int(b[87]),enabled:b[3]&16==0)
            guard (0...127).contains(rule.low),(rule.low...127).contains(rule.high),(0...127).contains(rule.velocityLow),(max(1,rule.velocityLow)...127).contains(rule.velocityHigh) else{throw MainStagePatch.Failure.invalid("Invalid EXS group ranges.")}
            native.append(layer);rules.append(rule)
        }
        guard !native.isEmpty else{throw MainStagePatch.Failure.invalid("EXS has no playable native zones.")}
        instrument["Layers"]=native;instrument["voice count"]=64;state["Instrument"]=instrument;state["file-references"]=references;state["gain"]=0;state["name"]=source.deletingPathExtension().lastPathComponent
        let program=NativeSamplerProgram(groups:rules,notes:notes.sorted(),compactGroups:true,conversionVersion:2,amplitudeEnvelope:amplitude)
        guard program.valid else{throw MainStagePatch.Failure.invalid("EXS native group plan is invalid.")}
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:output,options:.atomic)
        return program
    }
}
