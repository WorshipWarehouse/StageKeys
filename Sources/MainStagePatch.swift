import Foundation
import CryptoKit

/// Reads documents as data. Never instantiates archived Objective-C classes,
/// executes MIDI scripts, launches MainStage, or substitutes a synth sound.
enum MainStagePatch {
    struct Device:Codable,Equatable {
        var name:String
        var offset:Int
        var byteCount:Int
        var format:String
    }
    struct Channel:Codable,Equatable {
        var name:String
        var file:String
        var sha256:String
        var instruments:[String]
        var devices:[Device]
        var hasMappings:Bool
        var hasMIDIState:Bool
    }
    struct Report:Codable,Equatable {
        var version=1
        var name:String
        var channels:[Channel]
        var blockers:[String]
        var preservedFiles:[String:String]
        var complete:Bool {blockers.isEmpty}
    }
    enum Failure:LocalizedError {
        case invalid(String)
        var errorDescription:String? {if case .invalid(let message)=self{return message};return nil}
    }
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    private static func contained(_ file:URL,in root:URL)->Bool {
        file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path+"/")
    }
    static func read(_ file:URL,in root:URL)throws->Data {
        guard contained(file,in:root) else{throw Failure.invalid("A patch reference leaves the selected patch folder.")}
        let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<=16_000_000 else{throw Failure.invalid("Invalid or oversized MainStage document.")}
        let data=try Data(contentsOf:file)
        guard data.count<=16_000_000 else{throw Failure.invalid("Oversized MainStage document.")}
        return data
    }
    static func devices(_ data:Data)throws->[Device] {
        guard data.count>=36,data.prefix(4)==Data("OCuA".utf8) else{throw Failure.invalid("Unsupported channel-strip version; original bytes will not be treated as a sampler preset.")}
        let bytes=[UInt8](data)
        func u32(_ start:Int)->Int {(0..<4).reduce(0){$0 | Int(bytes[start+$1]) << ($1*8)}}
        var found:[Device]=[],position=0
        while position+172<=bytes.count {
            defer{position+=1}
            guard Array(bytes[position..<position+4])==Array("UCuA".utf8) else{continue}
            let start=position+28,size=u32(start)
            guard size>=144,size<=bytes.count-start-8 else{continue}
            let signature=String(bytes:bytes[start+140..<start+144],encoding:.ascii)
            guard signature=="GAME" || signature=="MELC" else{continue}
            let nameBytes=bytes[start+128..<start+140].prefix(while:{$0 != 0})
            guard !nameBytes.isEmpty,nameBytes.allSatisfy({(32...126).contains($0)}),let name=String(bytes:nameBytes,encoding:.ascii) else{continue}
            guard found.count<128 else{throw Failure.invalid("Too many channel-strip devices.")}
            found.append(Device(name:name,offset:position,byteCount:size+36,format:signature!))
            position=start+size+7
        }
        return found
    }
    static func instrumentReferences(_ data:Data)->[String] {
        // Observed EXS24 records prefix the saved basename with this signature.
        let marker=Data("MELCPMAS1MAS".utf8)
        var names:[String]=[],start=data.startIndex
        while start<data.endIndex,let range=data.range(of:marker,in:start..<data.endIndex) {
            let suffix=data[range.upperBound..<min(data.endIndex,range.upperBound+256)].prefix(while:{$0 != 0})
            if let name=String(data:suffix,encoding:.utf8),name.lowercased().hasSuffix(".exs"),name==URL(fileURLWithPath:name).lastPathComponent {names.append(name)}
            start=range.upperBound
        }
        return Array(Set(names)).sorted()
    }
    static func inspect(_ patch:URL)throws->Report {
        guard patch.pathExtension.lowercased()=="patch",(try patch.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])).isDirectory==true,
              (try patch.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else{throw Failure.invalid("Choose a MainStage .patch folder.")}
        let bytes=try read(patch.appendingPathComponent("data.plist"),in:patch)
        guard let document=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let channels=document["channels"] as? [[String:Any]],!channels.isEmpty,channels.count<=128 else{throw Failure.invalid("This patch does not contain a supported channel list.")}
        let patchData=document["patch"] as? [String:Any]
        let engine=patchData?["engineNode"] as? [String:Any]
        let authoredName=engine?["name"] as? String ?? patch.deletingPathExtension().lastPathComponent
        guard authoredName.count<=200 else{throw Failure.invalid("The patch name exceeds the supported length.")}
        var result=Report(name:authoredName,channels:[],blockers:[],preservedFiles:["data.plist":digest(bytes)])
        for channel in channels {
            guard let filename=channel["Filename"] as? String,filename==URL(fileURLWithPath:filename).lastPathComponent,filename.lowercased().hasSuffix(".cst") else{throw Failure.invalid("Unsafe or unsupported channel-strip reference.")}
            let data=try read(patch.appendingPathComponent(filename),in:patch)
            let name=channel["Channel_name"] as? String ?? filename
            guard name.count<=200 else{throw Failure.invalid("A channel name exceeds the supported length.")}
            var deviceList:[Device]=[]
            do{deviceList=try devices(data)}catch{result.blockers.append("\(name): \(error.localizedDescription)")}
            let instruments=instrumentReferences(data)
            let mappings=data.range(of:Data("MAPlugInParameterMapping".utf8)) != nil || data.range(of:Data("MABaseplateParameterMapping".utf8)) != nil
            let midi=channel["MIDITransform"] != nil
            result.channels.append(Channel(name:name,file:filename,sha256:digest(data),instruments:instruments,devices:deviceList,hasMappings:mappings,hasMIDIState:midi))
            result.preservedFiles[filename]=digest(data)
            // Retention is lossless; playback translation must be proven separately.
            // Merely finding an EXS filename is not a complete patch conversion.
            result.blockers.append("\(name): proprietary channel-strip parameter/routing translation is not yet verified.")
            if instruments.isEmpty,channel["Channel_inputIsBus"] as? Bool != true {result.blockers.append("\(name): no portable EXS sampler reference was found.")}
            if mappings {result.blockers.append("\(name): Smart Control macro mappings require translation.")}
        }
        return result
    }
    /// Archive all source files byte-for-byte. Paths, hashes, mappings, effects,
    /// MIDI state and unknown records survive, but no incomplete sound is added.
    static func retain(_ patch:URL,to destination:URL)throws->Report {
        let report=try inspect(patch)
        let manager=FileManager.default
        let root=patch.resolvingSymlinksInPath().standardizedFileURL
        guard !manager.fileExists(atPath:destination.path) else{throw Failure.invalid("The conversion archive already exists.")}
        try manager.createDirectory(at:destination,withIntermediateDirectories:true)
        do {
            let source=destination.appendingPathComponent("Source.patch",isDirectory:true)
            try manager.createDirectory(at:source,withIntermediateDirectories:false)
            guard let enumeration=manager.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey]) else{throw Failure.invalid("Could not read patch files.")}
            var count=0,total=0
            for case let file as URL in enumeration {
                count+=1;guard count<=4096,contained(file,in:root) else{throw Failure.invalid("Patch file limit or unsafe reference.")}
                let values=try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey])
                guard values.isSymbolicLink != true else{throw Failure.invalid("Symbolic links cannot be archived as patch assets.")}
                let relative=String(file.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(root.path.count+1)),target=source.appendingPathComponent(relative)
                if values.isDirectory==true {try manager.createDirectory(at:target,withIntermediateDirectories:true)}
                else {
                    let data=try read(file,in:root);total+=data.count
                    guard total<=128_000_000 else{throw Failure.invalid("Patch archive exceeds 128 MB.")}
                    try manager.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try data.write(to:target,options:.atomic)
                    guard try Data(contentsOf:target)==data else{throw Failure.invalid("Patch archive verification failed.")}
                }
            }
            for (name,hash) in report.preservedFiles {guard digest(try read(source.appendingPathComponent(name),in:source))==hash else{throw Failure.invalid("Source changed while archiving. Retry the import.")}}
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(report).write(to:destination.appendingPathComponent("conversion-report.json"),options:.atomic)
            return report
        }catch{try? manager.removeItem(at:destination);throw error}
    }
}
