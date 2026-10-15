import Foundation

/// Modern MainStage Auto Sampler writes long sample names in extended EXS
/// fields. AUSampler resolves the short legacy name instead. Normalize only
/// these references in a temporary copy; leave zones/groups/loops unchanged.
enum EXSCaptureCompatibility {
    static func withCompatiblePreset<T>(_ preset:URL, sampleRoot:URL, load:(URL,URL)throws->T) throws -> T {
        let values=try preset.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile == true,(values.fileSize ?? Int.max)<=16*1024*1024 else { throw ExternalInstrumentError.unsupportedFormat }
        var bytes=try Data(contentsOf:preset)
        guard bytes.count<=16*1024*1024 else { throw ExternalInstrumentError.unsupportedFormat }
        func u32(_ index:Int)->Int { (0..<4).reduce(0){$0 | Int(bytes[index+$1]) << (8*$1)} }
        guard bytes.count>=84, u32(0)==0x101 || u32(0)==0x40000101 else { return try load(preset,sampleRoot) }
        var extended:[Int]=[],offset=0
        while offset<bytes.count {
            guard offset+84<=bytes.count,bytes.subdata(in:offset+16..<offset+20)==Data("TBOS".utf8) else { throw ExternalInstrumentError.unsupportedFormat }
            let size=u32(offset+4),signature=u32(offset)
            guard size<=bytes.count-offset-84 else { throw ExternalInstrumentError.unsupportedFormat }
            if signature==0x03000101 || signature==0x43000101 {
                if size>=1624 { extended.append(offset) }
                else { return try load(preset,sampleRoot) }
            }
            offset+=84+size
        }
        guard !extended.isEmpty,extended.count<=4096 else { return try load(preset,sampleRoot) }
        let manager=FileManager.default,root=sampleRoot.resolvingSymlinksInPath().standardizedFileURL
        let temporary=manager.temporaryDirectory.appendingPathComponent("StageKeys-EXS-"+UUID().uuidString,isDirectory:true)
        try manager.createDirectory(at:temporary,withIntermediateDirectories:false)
        defer { try? manager.removeItem(at:temporary) }
        func string(_ start:Int,_ length:Int)throws->String {
            let field=bytes.subdata(in:start..<start+length)
            guard let end=field.firstIndex(of:0),let value=String(data:field.prefix(end),encoding:.utf8) else { throw ExternalInstrumentError.unsupportedFormat }
            return value
        }
        func replace(_ start:Int,_ length:Int,_ value:String)throws {
            let data=Data(value.utf8)
            guard data.count<length else { throw ExternalInstrumentError.unsupportedFormat }
            bytes.replaceSubrange(start..<start+length,with:data+Data(repeating:0,count:length-data.count))
        }
        var copied:[URL:URL]=[:]
        for position in extended {
            let name=try string(position+420,256),directory=try string(position+684,1024)
            guard !name.isEmpty,name==URL(fileURLWithPath:name).lastPathComponent else { throw ExternalInstrumentError.unsupportedFormat }
            let original=URL(fileURLWithPath:directory,isDirectory:true).appendingPathComponent(name)
            let parts=original.pathComponents.filter{$0 != "/" && $0 != ".." && $0 != "."}
            let suffixes=(1...max(1,min(16,parts.count))).map{root.appendingPathComponent(parts.suffix($0).joined(separator:"/"))}
            guard let source=([original]+suffixes).map({$0.resolvingSymlinksInPath().standardizedFileURL}).first(where:{
                $0.path.hasPrefix(root.path+"/") && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true
            }),["wav","aif","aiff","caf"].contains(source.pathExtension.lowercased()) else {
                throw NSError(domain:"StageKeysEXS",code:2,userInfo:[NSLocalizedDescriptionKey:"Missing capture sample: \(name). Choose its sample folder."])
            }
            let destination:URL
            if let previous=copied[source] { destination=previous }
            else {
                destination=temporary.appendingPathComponent("s"+String(copied.count)+"."+source.pathExtension.lowercased())
                try manager.copyItem(at:source,to:destination);copied[source]=destination
            }
            try replace(position+20,64,destination.lastPathComponent)
            try replace(position+164,256,temporary.path)
            try replace(position+420,256,destination.lastPathComponent)
            try replace(position+684,1024,temporary.path)
        }
        let compatible=temporary.appendingPathComponent("Instrument.exs")
        try bytes.write(to:compatible,options:.atomic)
        return try load(compatible,temporary)
    }
}
