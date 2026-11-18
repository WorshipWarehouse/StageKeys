import Foundation
import zlib

/// Read-only Stage 4 bundle admission. No archive path is ever extracted to disk.
/// Program parameters/sample engines are not inferred from dependency filenames.
enum NordBundle {
    struct Failure: LocalizedError { let reason:String;var errorDescription:String?{"Nord bundle: "+reason} }
    struct Entry:Equatable {
        let name:String
        let bytes,compressedBytes,method,flags,offset:Int
        let checksum:UInt32
        var isPiano:Bool {name.lowercased().hasSuffix(".npno")}
    }
    struct Program:Equatable {let name:String;let dependencies:[String]}
    struct Preview {
        let sourceName,identity:String
        let sourceBytes:Int
        let entries:[Entry]
        let programs:[Program]
        var pianos:[Entry] {entries.filter(\.isPiano)}
        var samples:[Entry] {entries.filter{$0.name.lowercased().hasSuffix(".nsmp4")}}
        let limitation="Nord Stage 4 program parameters, synth/organ engines, sample instruments and source effects are not converted here. Inspecting or converting a piano does not recreate an artist program."
    }
    static let fileLimit=2_000_000_000,entryLimit=512<<20
    private static func fail(_ reason:String)throws->Never {throw Failure(reason:reason)}
    private static func u16(_ data:Data,_ at:Int)->Int {Int(data[at]) | Int(data[at+1])<<8}
    private static func u32(_ data:Data,_ at:Int)->Int {u16(data,at) | u16(data,at+2)<<16}
    private static func safe(_ name:String)->Bool {
        let path=name.hasSuffix("/") ? String(name.dropLast()):name
        return !path.isEmpty && name.utf8.count<=4096 && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") &&
            !path.unicodeScalars.contains{$0.value<32} && path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy{!$0.isEmpty && $0 != "." && $0 != ".."}
    }
    private static func crc(_ data:Data)->UInt32 {
        data.withUnsafeBytes {raw in UInt32(zlib.crc32(0,raw.bindMemory(to:Bytef.self).baseAddress,uInt(raw.count)))}
    }
    private final class Reader {
        let handle:FileHandle,size:Int
        let sourceName:String
        let cancelled:()->Bool
        init(_ url:URL,cancelled:@escaping ()->Bool)throws {
            var current=url;current.removeAllCachedResourceValues()
            let values=try current.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard values.isRegularFile==true,values.isSymbolicLink != true,let bytes=values.fileSize,bytes>=22,bytes<=fileLimit else{try fail("Choose a regular bundle no larger than 2 GB.")}
            size=bytes;sourceName=url.lastPathComponent;self.cancelled=cancelled;handle=try FileHandle(forReadingFrom:url)
        }
        deinit {try? handle.close()}
        func read(_ at:Int,_ count:Int)throws->Data {
            guard at>=0,count>=0,at<=size,count<=size-at else{try fail("A ZIP span is outside the selected file.")}
            try handle.seek(toOffset:UInt64(at));var data=Data();data.reserveCapacity(count)
            while data.count<count {
                if cancelled(){throw CancellationError()}
                guard let chunk=try handle.read(upToCount:min(1<<20,count-data.count)),!chunk.isEmpty else{try fail("The selected bundle was truncated while reading.")}
                data.append(chunk)
            }
            return data
        }
        func layout(_ entry:Entry,before central:Int)throws->(Range<Int>,Range<Int>) {
            let local=try read(entry.offset,30)
            guard u32(local,0)==0x04034b50,u16(local,6)==entry.flags,u16(local,8)==entry.method else{try fail("Local and central ZIP headers disagree.")}
            let n=u16(local,26),extra=u16(local,28)
            let name=try read(entry.offset+30,n)
            guard name==Data(entry.name.utf8) else{try fail("A local ZIP filename differs from its directory entry.")}
            let start=entry.offset+30+n+extra,end=start+entry.compressedBytes
            guard end<=central else{try fail("A payload overlaps the ZIP directory.")}
            var rangeEnd=end
            if entry.flags&8 != 0 {
                let first=try read(end,4),hasSignature=u32(first,0)==0x08074b50
                let descriptor=try read(end+(hasSignature ? 4:0),12)
                guard u32(descriptor,0)==Int(entry.checksum),u32(descriptor,4)==entry.compressedBytes,u32(descriptor,8)==entry.bytes else{try fail("A ZIP data descriptor disagrees with its directory.")}
                rangeEnd+=hasSignature ? 16:12
            } else {
                guard u32(local,14)==Int(entry.checksum),u32(local,18)==entry.compressedBytes,u32(local,22)==entry.bytes else{try fail("Local ZIP sizes or checksum disagree.")}
            }
            guard rangeEnd<=central else{try fail("A ZIP descriptor overlaps its directory.")}
            return (start..<end,entry.offset..<rangeEnd)
        }
        func payload(_ entry:Entry,before central:Int)throws->Data {
            let ranges=try layout(entry,before:central)
            let packed=try read(ranges.0.lowerBound,entry.compressedBytes)
            let result:Data
            if entry.method==0 {
                guard entry.bytes==entry.compressedBytes else{try fail("A stored ZIP entry has inconsistent lengths.")};result=packed
            } else {
                guard entry.bytes>0,!packed.isEmpty else{try fail("Empty deflate payload is not supported.")}
                var stream=z_stream()
                guard inflateInit2_(&stream,-MAX_WBITS,ZLIB_VERSION,Int32(MemoryLayout<z_stream>.size))==Z_OK else{try fail("Cannot initialize ZIP decompression.")}
                defer{inflateEnd(&stream)}
                var output=Data(count:entry.bytes)
                let status=output.withUnsafeMutableBytes {dest in packed.withUnsafeBytes {src -> Int32 in
                    stream.next_in=UnsafeMutablePointer(mutating:src.bindMemory(to:Bytef.self).baseAddress);stream.avail_in=uInt(src.count)
                    stream.next_out=dest.bindMemory(to:Bytef.self).baseAddress;stream.avail_out=uInt(dest.count)
                    return inflate(&stream,Z_FINISH)
                }}
                guard status==Z_STREAM_END,stream.total_in==packed.count,stream.total_out==entry.bytes else{try fail("Deflate output does not match the bounded declared size.")};result=output
            }
            if cancelled(){throw CancellationError()}
            guard crc(result)==entry.checksum else{try fail("An embedded file failed its ZIP checksum.")}
            return result
        }
    }
    private struct Directory {let entries:[Entry];let offset:Int;let bytes:Data}
    private static func directory(_ reader:Reader)throws->Directory {
        let count=min(reader.size,65557),tail=try reader.read(reader.size-count,count)
        var end:Int?
        for at in stride(from:tail.count-22,through:0,by:-1) where u32(tail,at)==0x06054b50 {
            if at+22+u16(tail,at+20)==tail.count {end=at;break}
        }
        guard let end else{try fail("Missing or truncated ZIP end record.")}
        let records=u16(tail,end+10),length=u32(tail,end+12),offset=u32(tail,end+16)
        guard u16(tail,end+4)==0,u16(tail,end+6)==0,u16(tail,end+8)==records,records>0,records<=4096,length<=4<<20,
              offset+length==reader.size-count+end else{try fail("Multi-disk, ZIP64 or oversized ZIP directories are unsupported.")}
        let data=try reader.read(offset,length)
        var at=0,entries:[Entry]=[],names=Set<String>(),total=0
        for _ in 0..<records {
            if reader.cancelled(){throw CancellationError()}
            guard at+46<=data.count,u32(data,at)==0x02014b50 else{try fail("Invalid ZIP central-directory record.")}
            let n=u16(data,at+28),extra=u16(data,at+30),comment=u16(data,at+32),end=at+46+n+extra+comment
            guard n>0,n<=4096,end<=data.count,let name=String(data:data.subdata(in:at+46..<at+46+n),encoding:.utf8),safe(name) else{try fail("Unsafe or unsupported ZIP filename.")}
            let canonical=name.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(canonical).inserted else{try fail("Duplicate or colliding ZIP filenames.")}
            let flags=u16(data,at+8),method=u16(data,at+10),bytes=u32(data,at+24),packed=u32(data,at+20),start=u32(data,at+42)
            let unixMode=(u32(data,at+38)>>16)&0xf000
            guard flags & ~0x080e == 0,method==0 || method==8,unixMode != 0xa000,u16(data,at+34)==0,
                  bytes<=entryLimit,packed<=entryLimit,start+30<=offset else{try fail("Encrypted, linked, unsupported or oversized ZIP entry.")}
            total+=bytes;guard total<=fileLimit else{try fail("Declared bundle output exceeds 2 GB.")}
            entries.append(Entry(name:name,bytes:bytes,compressedBytes:packed,method:method,flags:flags,offset:start,checksum:UInt32(u32(data,at+16))))
            at=end
        }
        guard at==data.count else{try fail("Unexpected ZIP directory data.")}
        return Directory(entries:entries,offset:offset,bytes:data)
    }
    private final class Manifest:NSObject,XMLParserDelegate {
        var depth=0,sawRoot=false,programs:[Program]=[],problem:Failure?
        func reject(_ parser:XMLParser,_ text:String){problem=Failure(reason:text);parser.abortParsing()}
        func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes attrs:[String:String]) {
            depth+=1
            if depth==1 {
                guard !sawRoot,name=="bundle",attrs["version"]=="1",attrs["product"]=="46",attrs.count<=16 else{reject(parser,"This is not a supported Stage 4 bundle manifest.");return};sawRoot=true
            } else if depth==2 {
                guard name=="file",programs.count<4096,let file=attrs["name"],safe(file),file.lowercased().hasSuffix(".ns4p"),let raw=attrs["depCnt"],let count=Int(raw),(0...32).contains(count),attrs.count==count+2 else{reject(parser,"Invalid program dependency declaration.");return}
                var dependencies:[String]=[]
                for i in 0..<count {guard let value=attrs["dep\(i)"],safe(value) else{reject(parser,"Unsafe or missing program dependency.");return};dependencies.append(value)}
                programs.append(Program(name:file,dependencies:dependencies))
            } else {reject(parser,"Unexpected nested bundle metadata.")}
        }
        func parser(_ parser:XMLParser,didEndElement:String,namespaceURI:String?,qualifiedName:String?){depth-=1}
        func parser(_ parser:XMLParser,foundCharacters string:String){if !string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {reject(parser,"Unexpected bundle metadata text.")}}
    }
    static func inspect(_ url:URL,cancelled:@escaping ()->Bool={false})throws->Preview {
        let reader=try Reader(url,cancelled:cancelled)
        return try inspect(reader).0
    }
    private static func inspect(_ reader:Reader)throws->(Preview,Directory) {
        let dir=try directory(reader)
        guard let meta=dir.entries.first(where:{$0.name=="meta.xml"}),meta.bytes<=64<<10 else{try fail("Missing or oversized bundle manifest.")}
        let spans=try dir.entries.map{try reader.layout($0,before:dir.offset).1}.sorted{$0.lowerBound<$1.lowerBound}
        for i in spans.indices.dropFirst() {guard spans[i-1].upperBound<=spans[i].lowerBound else{try fail("ZIP entry spans overlap.")}}
        let data=try reader.payload(meta,before:dir.offset)
        guard let xml=String(data:data,encoding:.utf8),!xml.lowercased().contains("<!doctype"),!xml.lowercased().contains("<!entity") else{try fail("Unsupported XML declarations.")}
        let manifest=Manifest(),parser=XMLParser(data:data);parser.shouldResolveExternalEntities=false;parser.delegate=manifest
        guard parser.parse(),manifest.sawRoot,manifest.depth==0,!manifest.programs.isEmpty,manifest.problem==nil else{throw manifest.problem ?? Failure(reason:"Invalid bundle manifest.")}
        let known=Dictionary(uniqueKeysWithValues:dir.entries.map{($0.name,$0)})
        var seen=Set<String>()
        for program in manifest.programs {
            guard seen.insert(program.name).inserted,let entry=known[program.name],entry.bytes>=44,entry.bytes<=4096,
                  program.dependencies.allSatisfy({known[$0] != nil}) else{try fail("Missing, duplicate or oversized program/dependency.")}
            let bytes=try reader.payload(entry,before:dir.offset)
            guard bytes.prefix(4)==Data("CBIN".utf8),u32(bytes,4)==1,bytes.subdata(in:8..<12)==Data("ns4p".utf8),crc(Data(bytes.dropFirst(44)))==UInt32(u32(bytes,24)) else{try fail("A program container or body checksum is unsupported.")}
        }
        guard Set(dir.entries.filter{$0.name.lowercased().hasSuffix(".ns4p")}.map(\.name))==seen else{try fail("A program is omitted from the manifest.")}
        let identity=AssetDigest.sha256(dir.bytes+data+Data(String(reader.size).utf8))
        return (Preview(sourceName:reader.sourceName,identity:identity,sourceBytes:reader.size,entries:dir.entries,programs:manifest.programs),dir)
    }
    static func piano(_ name:String,from url:URL,preview:Preview,cancelled:@escaping ()->Bool={false})throws->Data {
        let reader=try Reader(url,cancelled:cancelled)
        let (current,dir)=try inspect(reader)
        guard current.identity==preview.identity,let entry=current.pianos.first(where:{$0.name==name}) else{try fail("The bundle changed or the selected piano is missing. Inspect it again.")}
        return try reader.payload(entry,before:dir.offset)
    }
}
