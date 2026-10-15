import Foundation
import CryptoKit
import zlib

/// Bounded reader for the observed pl-a Live Pack index. Only audio and
/// sample-preset members are extracted; no package content is executed.
enum AbletonArchive {
    static func sha256(_ url:URL)throws->String {
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var hash=SHA256()
        while let bytes=try handle.read(upToCount:1024*1024),!bytes.isEmpty{hash.update(data:bytes)}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    struct Member {let name:String;let offset:Int;let size:Int}
    static func members(_ raw:Data)throws->[Member] {
        guard raw.count>=16,raw.prefix(4)==Data("pl-a".utf8) else{throw AbletonImportError.invalid("Unsupported Live Pack header.")}
        func integer(_ at:Int,_ length:Int)throws->UInt64 {
            guard at>=0,at<=raw.count-length else{throw AbletonImportError.invalid("Truncated Live Pack index.")}
            return (0..<length).reduce(0){$0 | UInt64(raw[at+$1]) << (8*$1)}
        }
        let index64=try integer(4,8)
        guard index64>=16,index64<raw.count,UInt64(raw.count)-index64<=32*1024*1024 else{throw AbletonImportError.invalid("Invalid Live Pack index bounds.")}
        let index=Int(index64),marker=Data([0,11])+Data("PackageItem".utf8)
        var cursor=index,result:[Member]=[]
        while cursor<raw.count,let range=raw.range(of:marker,options:[],in:cursor..<raw.count) {
            let position=range.upperBound;cursor=position
            guard position+8<=raw.count else{break}
            let length=Int(try integer(position+4,4))
            guard length>0,length<=256,position+8+length*2+28<=raw.count else{continue}
            guard let name=String(data:raw.subdata(in:(position+8)..<(position+8+length*2)),encoding:.utf16LittleEndian) else{continue}
            let ext=URL(fileURLWithPath:name).pathExtension.lowercased()
            guard ["adg","adv","aif","aiff","wav","caf","flac"].contains(ext) else{continue}
            guard !name.contains("/"),!name.contains("\\"),!name.contains("\0"),name != ".",name != ".." else{throw AbletonImportError.invalid("Unsafe archive member name.")}
            let fields=position+8+length*2,offset64=try integer(fields+12,8),size64=try integer(fields+20,8)
            guard offset64>=16,size64>=4,size64<=512*1024*1024,offset64<index64,size64<=index64-offset64 else{throw AbletonImportError.invalid("Invalid archive member bounds.")}
            let offset=Int(offset64),size=Int(size64),signature=raw.subdata(in:offset..<(offset+4))
            if ext == "adg" || ext == "adv" {
                guard signature.starts(with:[0x1f,0x8b]) else{throw AbletonImportError.invalid("Invalid preset signature.")}
            } else{guard ["FORM","RIFF","caff","fLaC"].contains(String(decoding:signature,as:UTF8.self)) else{throw AbletonImportError.invalid("Invalid audio signature.")}}
            result.append(Member(name:name,offset:offset,size:size))
            guard result.count<=20_000 else{throw AbletonImportError.invalid("Too many archive members.")}
        }
        guard !result.isEmpty else{throw AbletonImportError.invalid("No supported Live Pack members.")}
        return result
    }
    /// The caller owns and removes the returned temporary directory after import.
    static func extract(_ source:URL)throws->URL {
        let access=source.startAccessingSecurityScopedResource();defer{if access{source.stopAccessingSecurityScopedResource()}}
        let fm=FileManager.default,folder=fm.temporaryDirectory.appendingPathComponent("StageKeys-Ableton-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:false)
        do {
            let spool=folder.appendingPathComponent("Pack.raw")
            guard fm.createFile(atPath:spool.path,contents:nil),let gz=gzopen(source.path,"rb") else{throw AbletonImportError.invalid("Cannot read compressed Live Pack.")}
            defer{gzclose(gz)}
            let handle=try FileHandle(forWritingTo:spool)
            do {
                defer{try? handle.close()}
                var buffer=[UInt8](repeating:0,count:1024*1024),total:Int64=0
                while true {
                    let count=gzread(gz,&buffer,UInt32(buffer.count))
                    guard count>=0 else{throw AbletonImportError.invalid("Corrupt gzip Live Pack.")}
                    if count==0{break};total+=Int64(count)
                    guard total<=8*1024*1024*1024 else{throw AbletonImportError.invalid("Expanded Live Pack exceeds 8 GB limit.")}
                    try handle.write(contentsOf:Data(buffer.prefix(Int(count))))
                }
            }
            let raw=try Data(contentsOf:spool,options:.alwaysMapped),entries=try members(raw)
            for entry in entries {
                let isPreset=["adg","adv"].contains(URL(fileURLWithPath:entry.name).pathExtension.lowercased())
                let parent=folder.appendingPathComponent(isPreset ? "Presets" : "Samples",isDirectory:true)
                try fm.createDirectory(at:parent,withIntermediateDirectories:true)
                let target=parent.appendingPathComponent(entry.name),bytes=raw.subdata(in:entry.offset..<(entry.offset+entry.size))
                if fm.fileExists(atPath:target.path) {
                    guard try sha256(target)==SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined() else{throw AbletonImportError.invalid("Ambiguous duplicate archive filename.")}
                } else{try bytes.write(to:target)}
            }
            try fm.removeItem(at:spool)
            return folder
        } catch{try? fm.removeItem(at:folder);throw error}
    }
}
