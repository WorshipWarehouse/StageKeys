import Foundation
import zlib

@main struct NordBundleTests {
    struct File {var name:String;var data:Data;var flags=0;var method=0;var declared:Int?}
    static func crc(_ data:Data)->UInt32 {
        var c:UInt32=0xffffffff
        for b in data {c ^= UInt32(b);for _ in 0..<8 {c=(c&1 != 0) ? (c>>1)^0xedb88320:c>>1}}
        return c^0xffffffff
    }
    static func zip(_ files:[File])->Data {
        var local=Data(),directory=Data()
        func number(_ v:Int,_ width:Int)->Data {Data((0..<width).map{UInt8(truncatingIfNeeded:v>>($0*8))})}
        for f in files {
            let start=local.count,name=Data(f.name.utf8),checksum=Int(crc(f.data))
            var packed=f.data
            if f.method==8 {
                var stream=z_stream();precondition(deflateInit2_(&stream,Z_DEFAULT_COMPRESSION,Z_DEFLATED,-MAX_WBITS,8,Z_DEFAULT_STRATEGY,ZLIB_VERSION,Int32(MemoryLayout<z_stream>.size))==Z_OK)
                defer{deflateEnd(&stream)}
                var output=Data(count:f.data.count+1024)
                let status=output.withUnsafeMutableBytes {out in f.data.withUnsafeBytes {input -> Int32 in
                    stream.next_in=UnsafeMutablePointer(mutating:input.bindMemory(to:Bytef.self).baseAddress);stream.avail_in=uInt(input.count)
                    stream.next_out=out.bindMemory(to:Bytef.self).baseAddress;stream.avail_out=uInt(out.count)
                    return deflate(&stream,Z_FINISH)
                }}
                precondition(status==Z_STREAM_END);packed=Data(output.prefix(Int(stream.total_out)))
            }
            let localFields:[Data]=[number(0x04034b50,4),number(20,2),number(f.flags,2),number(f.method,2),number(0,4),number(checksum,4),number(packed.count,4),number(f.declared ?? f.data.count,4),number(name.count,2),number(0,2),name,packed]
            for field in localFields {local.append(field)}
            if f.flags&8 != 0 {
                for field in [number(0x08074b50,4),number(checksum,4),number(packed.count,4),number(f.declared ?? f.data.count,4)] {local.append(field)}
            }
            let centralFields:[Data]=[number(0x02014b50,4),number(20,2),number(20,2),number(f.flags,2),number(f.method,2),number(0,4),number(checksum,4),number(packed.count,4),number(f.declared ?? f.data.count,4),number(name.count,2),number(0,2),number(0,2),number(0,2),number(0,2),number(0,4),number(start,4),name]
            for field in centralFields {directory.append(field)}
        }
        let end:[Data]=[number(0x06054b50,4),number(0,4),number(files.count,2),number(files.count,2),number(directory.count,4),number(local.count,4),number(0,2)]
        var result=local;result.append(directory);for field in end {result.append(field)};return result
    }
    @MainActor static func main() async throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source=root.appendingPathComponent("Original generated.ns4pbundle"),piano=TestFixtures.nordPiano()
        var program=Data(repeating:0,count:108);program.replaceSubrange(0..<4,with:Data("CBIN".utf8));program[4]=1;program.replaceSubrange(8..<12,with:Data("ns4p".utf8))
        let checksum=crc(Data(program.dropFirst(44)));for i in 0..<4 {program[24+i]=UInt8(truncatingIfNeeded:checksum>>(i*8))}
        let xml="<bundle version=\"1\" product=\"46\"><file name=\"Program/Original.ns4p\" depCnt=\"1\" dep0=\"Piano/Original.npno\"/></bundle>"
        let files=[File(name:"meta.xml",data:Data(xml.utf8)),File(name:"Program/Original.ns4p",data:program),File(name:"Piano/Original.npno",data:piano)]
        let bytes=zip(files);try bytes.write(to:source)
        let preview=try NordBundle.inspect(source)
        assert(preview.programs.count==1 && preview.pianos.count==1 && preview.samples.isEmpty)
        assert(preview.programs[0].dependencies==["Piano/Original.npno"])
        assert(preview.limitation.contains("does not recreate"))
        let embedded=try NordBundle.piano("Piano/Original.npno",from:source,preview:preview)
        assert(embedded==piano)
        assert(try! Data(contentsOf:source)==bytes)
        let converted=try NordNative.preview(embedded);assert(converted.zones.count==6)
        var compressed=files;compressed[2].method=8
        try zip(compressed).write(to:source)
        let compressedPreview=try NordBundle.inspect(source)
        assert(try! NordBundle.piano("Piano/Original.npno",from:source,preview:compressedPreview)==piano)
        do {_ = try NordBundle.piano("Piano/Original.npno",from:source,preview:preview);fatalError("Stale bundle preview accepted")}catch{}
        func refuses(_ files:[File]) throws {
            try zip(files).write(to:source)
            do {_ = try NordBundle.inspect(source);fatalError("Unsafe ZIP accepted")}catch{}
        }
        try refuses(files+[File(name:"../escape",data:Data())])
        try refuses(files+[File(name:"/absolute",data:Data())])
        try refuses(files+[File(name:"Piano/ORIGINAL.NPNO",data:piano)])
        var descriptor=files;descriptor[2].flags=8
        try zip(descriptor).write(to:source)
        let descriptorPreview=try NordBundle.inspect(source)
        assert(try! NordBundle.piano("Piano/Original.npno",from:source,preview:descriptorPreview)==piano)
        var badDescriptor=zip(descriptor)
        let signature=badDescriptor.range(of:Data([0x50,0x4b,0x07,0x08]))!
        badDescriptor[signature.lowerBound+4] ^= 1
        try badDescriptor.write(to:source)
        do {_ = try NordBundle.inspect(source);fatalError("Bad descriptor accepted")}catch{}
        var linked=bytes
        let central=linked.range(of:Data([0x50,0x4b,0x01,0x02]))!.lowerBound
        linked[central+40]=0;linked[central+41]=0xa0
        try linked.write(to:source)
        do {_ = try NordBundle.inspect(source);fatalError("Symbolic-link entry accepted")}catch{}
        var zip64=bytes
        let end=zip64.count-22
        for i in 0..<4 {zip64[end+16+i]=255}
        try zip64.write(to:source)
        do {_ = try NordBundle.inspect(source);fatalError("ZIP64 sentinel accepted")}catch{}
        var unsupported=files;unsupported[2].method=99;try refuses(unsupported)
        var encrypted=files;encrypted[1].flags=1;try refuses(encrypted)
        var oversized=files;oversized[2].declared=NordBundle.entryLimit+1;try refuses(oversized)
        var missing=files;missing.removeLast();try refuses(missing)
        var omitted=files;omitted.append(File(name:"Program/Omitted.ns4p",data:program));try refuses(omitted)
        var badProgram=files;badProgram[1].data[50]=1;try refuses(badProgram)
        var dtd=files;dtd[0].data=Data(("<!DOCTYPE bundle [<!ENTITY x SYSTEM 'file:///no-access'>]>"+xml).utf8);try refuses(dtd)
        var bad=bytes;bad[30]=UInt8(ascii:"x");try bad.write(to:source)
        do {_ = try NordBundle.inspect(source);fatalError("Local-header mismatch accepted")}catch{}
        try Data(bytes.dropLast()).write(to:source)
        do {_ = try NordBundle.inspect(source);fatalError("Truncated bundle accepted")}catch{}
        try bytes.write(to:source)
        do {_ = try NordBundle.inspect(source,cancelled:{true});fatalError("Cancelled bundle inspection accepted")}catch{}
        var corrupt=bytes
        // A piano payload has its own checksum, verified when explicitly selected.
        let name=Data("Piano/Original.npno".utf8)
        let localHeader=preview.pianos[0].offset+30+name.count
        corrupt[localHeader+50] ^= 1
        try corrupt.write(to:source)
        let intactDirectory=try NordBundle.inspect(source)
        do {_ = try NordBundle.piano("Piano/Original.npno",from:source,preview:intactDirectory);fatalError("Bad embedded CRC accepted")}catch{}
        // The production Store never turns a bundle inspection into a patch or
        // silently converts the artist program. Only explicit piano confirmation commits.
        try bytes.write(to:source)
        let store=PerformanceStore()
        func wait() async throws {
            let deadline=Date().addingTimeInterval(15)
            while store.libraryImportBusy && Date()<deadline {try await Task.sleep(nanoseconds:5_000_000)}
            assert(!store.libraryImportBusy)
        }
        store.inspectNordBundle(source);try await wait()
        assert(store.nordBundlePreview?.programs.count==1 && store.nordImportPreview==nil && store.librarySounds.isEmpty)
        store.inspectNordBundlePiano("Piano/Original.npno");try await wait()
        assert(store.nordImportPreview != nil && store.librarySounds.isEmpty)
        assert(store.nordImportPreview!.notes.last!.contains("does not recreate"))
        store.importNordSound();try await wait()
        assert(store.librarySounds.count==1 && store.librarySounds[0].id==converted.identity)
        let catalog=root.appendingPathComponent("sound-library.json"),saved=try Data(contentsOf:catalog)
        store.inspectNordBundle(source);try await wait()
        store.inspectNordBundlePiano("Piano/Original.npno");store.discardNordImport();try await wait()
        assert(store.nordBundlePreview==nil && store.nordImportPreview==nil)
        store.inspectNordBundle(source);store.cancelLibraryImport();try await wait()
        assert(store.nordBundlePreview==nil && (try! Data(contentsOf:catalog))==saved)
        assert((try! Data(contentsOf:source))==bytes)
        print("PASS Nord bundles: stored/deflate original PCM inputs, manifest dependencies, explicit untranslated programs, changed/cancelled/corrupt/truncated/unsafe/encrypted/oversized refusal")
    }
}
