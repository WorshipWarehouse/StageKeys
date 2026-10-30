import Foundation
import CryptoKit

/// Optional sound pack. The application has no build/runtime dependency on a pack.
enum LibraryBackup {
    struct Manifest:Codable {var format:String;var version:Int;var files:[String:String]}
    struct Pack {var root:URL;var manifest:Manifest;var sounds:[LibrarySound]}
    static let token="@STAGEKEYS_LIBRARY@"
    static func read(_ folder:URL)throws->Pack {
        let root=folder.resolvingSymlinksInPath().standardizedFileURL
        let file=root.appendingPathComponent("manifest.json")
        let manifest=try JSONDecoder().decode(Manifest.self,from:RecoverableSessionFile.read(file,limit:2_000_000))
        guard manifest.format=="stagekeys-private-library",manifest.version==1,manifest.files.count<=20000 else{throw ExternalInstrumentError.unsupportedFormat}
        let catalog=try asset("sound-library.json",in:root,manifest:manifest)
        let data=try RecoverableSessionFile.read(catalog,limit:16_000_000)
        let sounds=try JSONDecoder().decode([LibrarySound].self,from:data)
        try SoundLibrary.validate(sounds)
        return Pack(root:root,manifest:manifest,sounds:sounds)
    }
    static func asset(_ relative:String,in root:URL,manifest:Manifest)throws->URL {
        guard !relative.hasPrefix("/"),!relative.split(separator:"/").contains(".."),let expected=manifest.files[relative],expected.count==64,expected.allSatisfy({$0.isHexDigit}) else{throw MainStagePatch.Failure.invalid("Unsafe or unlisted library asset.")}
        let file=root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path+"/"),(try file.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile==true,try AssetDigest.sha256(file)==expected else{throw MainStagePatch.Failure.invalid("Library asset is missing or changed: "+relative+". Download Git LFS assets before importing.")}
        return file
    }
    static func preset(_ sound:ExternalSound,pack:Pack,to output:URL)throws {
        guard sound.kind == .samplerPreset,let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent else{throw ExternalInstrumentError.unsupportedFormat}
        let source=try asset("Imported Sounds/"+name,in:pack.root,manifest:pack.manifest)
        let data=try RecoverableSessionFile.read(source,limit:16_000_000);guard var state=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any],let refs=state["file-references"] as? [String:String] else{throw ExternalInstrumentError.unsupportedFormat}
        var relocated:[String:String]=[:]
        for (key,path) in refs {
            guard path.hasPrefix(token+"/") else{throw MainStagePatch.Failure.invalid("Pack samples must use portable library references.")}
            relocated[key]=try asset(String(path.dropFirst(token.count+1)),in:pack.root,manifest:pack.manifest).path
        }
        state["file-references"]=relocated
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:output,options:.atomic)
    }
}

extension LibraryBackup {
    static func portabilityIssue(_ entry:LibrarySound)->String? {
        guard let sound=entry.sound ?? entry.layer?.external else{return "Unconverted host preset requires MainStage on a Mac."}
        guard sound.kind == .samplerPreset,sound.nativeSampler != nil else{return sound.kind == .audioUnit ? "Audio Unit binaries and plug-in snapshots are not transferred. Install the appropriate AUv3 separately.":"Convert this sound to a native sampler instrument first."}
        guard entry.layer?.midiDestinationID == nil else{return "External MIDI destinations are device-specific."}
        return nil
    }
    private static func portableNotes(_ notes:[String])->[String] {
        notes.map{$0.replacingOccurrences(of:#"(?:file://)?/(?:Users|private|Library|Volumes|var|tmp)/[^\s,;]+"#,with:"[source location]",options:.regularExpression)}
    }
    private static func portableSound(_ sound:ExternalSound)->ExternalSound {
        var value=sound
        if var program=value.nativeSampler {program.notes=portableNotes(program.notes);value.nativeSampler=program}
        return value
    }
    /// Personal native sounds only: current per-sound processing travels, while
    /// session documents, plugin snapshots, source archives and ratings do not.
    static func write(_ entries:[LibrarySound],library:URL,to folder:URL)throws {
        guard !entries.isEmpty,entries.count<=4096,!FileManager.default.fileExists(atPath:folder.path),entries.allSatisfy({portabilityIssue($0)==nil}) else{throw MainStagePatch.Failure.invalid("Choose native sampler sounds only and a new destination.")}
        let manager=FileManager.default
        try manager.createDirectory(at:folder,withIntermediateDirectories:true)
        do {
            var manifest=Manifest(format:"stagekeys-private-library",version:1,files:[:]),catalog:[LibrarySound]=[]
            var written=Set<String>(),total:UInt64=0
            func record(_ relative:String)throws {
                let file=folder.appendingPathComponent(relative)
                total+=UInt64(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)
                guard total<=PersonalSoundArchive.byteLimit,manifest.files.count<19999 else{throw SetlistLibraryError.oversized}
                manifest.files[relative]=try AssetDigest.sha256(file)
            }
            for var entry in entries {
                guard let original=entry.sound ?? entry.layer?.external,let name=original.fileName,name==URL(fileURLWithPath:name).lastPathComponent else{throw ExternalInstrumentError.missingFile}
                let relative="Imported Sounds/"+name
                if written.insert(name).inserted {
                    let source=library.appendingPathComponent(relative)
                    var state=try PropertyListSerialization.propertyList(from:RecoverableSessionFile.read(source,limit:16_000_000),options:[],format:nil) as? [String:Any] ?? [:]
                    guard let refs=state["file-references"] as? [String:String],!refs.isEmpty else{throw ExternalInstrumentError.unsupportedFormat}
                    var rewritten:[String:String]=[:]
                    for (key,path) in refs {
                        guard let sample=path.hasPrefix("file://") ? URL(string:path):URL(fileURLWithPath:path) as URL? else{throw SetlistLibraryError.unsafeFile}
                        let resolved=sample.resolvingSymlinksInPath().standardizedFileURL
                        let managed=library.appendingPathComponent("Imported Sounds").resolvingSymlinksInPath().standardizedFileURL
                        guard resolved.path.hasPrefix(managed.path+"/"),["wav","aif","aiff","caf","flac"].contains(resolved.pathExtension.lowercased()) else{throw MainStagePatch.Failure.invalid("A sample is outside the managed library or has an unsupported portable format.")}
                        let values=try resolved.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]);guard values.isRegularFile==true,let size=values.fileSize,size>=0 else{throw ExternalInstrumentError.missingFile}
                        let hash=try AssetDigest.sha256(resolved),target="Imported Sounds/Samples/"+hash+"."+resolved.pathExtension.lowercased()
                        if manifest.files[target]==nil {
                            total+=UInt64(size);guard total<=PersonalSoundArchive.byteLimit else{throw SetlistLibraryError.oversized}
                            let output=folder.appendingPathComponent(target);try manager.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
                            try manager.copyItem(at:resolved,to:output)
                            guard try AssetDigest.sha256(output)==hash,try AssetDigest.sha256(resolved)==hash else{throw MainStagePatch.Failure.invalid("A sample changed while creating the pack.")}
                            manifest.files[target]=hash
                        }
                        rewritten[key]=token+"/"+target
                    }
                    state["file-references"]=rewritten
                    if let data=state["StageKeys.NativeSampler"] as? Data {
                        var program=try JSONDecoder().decode(NativeSamplerProgram.self,from:data);program.notes=portableNotes(program.notes)
                        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
                    }
                    func rejectAbsolute(_ value:Any)throws {
                        if let string=value as? String,string.hasPrefix("/") || string.hasPrefix("file://") {throw MainStagePatch.Failure.invalid("A preset contains a nonportable absolute path.")}
                        if let dictionary=value as? [String:Any] {for value in dictionary.values{try rejectAbsolute(value)}}
                        if let array=value as? [Any] {for value in array{try rejectAbsolute(value)}}
                    }
                    try rejectAbsolute(state)
                    let output=folder.appendingPathComponent(relative);try manager.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:output,options:.atomic)
                    try record(relative)
                }
                entry.sound=portableSound(original);entry.hostPath=nil;entry.sourceArchiveID=nil;entry.originalInstrument=nil;entry.previousImportedRack=nil;entry.originalName=nil
                entry.conversionNotes=portableNotes(entry.conversionNotes ?? [])
                if var layer=entry.layer {layer.external=portableSound(original);layer.pluginState=nil;entry.layer=layer}
                catalog.append(entry)
            }
            try SoundLibrary.validate(catalog)
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            let bytes=try encoder.encode(catalog);guard bytes.count<=16_000_000 else{throw SetlistLibraryError.oversized}
            try bytes.write(to:folder.appendingPathComponent("sound-library.json"));try record("sound-library.json")
            let manifestData=try encoder.encode(manifest)
            guard manifestData.count<=2_000_000,total+UInt64(manifestData.count)<=PersonalSoundArchive.byteLimit else{throw SetlistLibraryError.oversized}
            try manifestData.write(to:folder.appendingPathComponent("manifest.json"))
            _ = try read(folder) // The writer must satisfy the existing pack reader.
        } catch {try? manager.removeItem(at:folder);throw error}
    }
    static func exportArchive(_ entries:[LibrarySound],library:URL,to destination:URL)throws {
        let staging=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:staging)}
        try write(entries,library:library,to:staging)
        try PersonalSoundArchive.write(staging,to:destination)
    }
}

/// A streaming, uncompressed personal pack container, not a ZIP file. Bounded
/// records use SHA-256; extraction never trusts absolute paths, links or sizes.
enum PersonalSoundArchive {
    static let byteLimit:UInt64=2_000_000_000
    static let magic=Data("STAGEKEYSPACK\n1\n".utf8)
    private static func safe(_ path:String)->Bool {
        !path.isEmpty && path.utf8.count<=4096 && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") && path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy{!$0.isEmpty && $0 != "." && $0 != ".."}
    }
    private static func integer(_ value:UInt64,_ count:Int)->Data {Data((0..<count).map{UInt8(truncatingIfNeeded:value >> ($0*8))})}
    private static func exact(_ handle:FileHandle,_ count:Int)throws->Data {
        var result=Data()
        while result.count<count {guard let bytes=try handle.read(upToCount:count-result.count),!bytes.isEmpty else{throw CocoaError(.fileReadCorruptFile)};result.append(bytes)}
        return result
    }
    private static func number(_ handle:FileHandle,_ count:Int)throws->UInt64 {let data=try exact(handle,count);return data.enumerated().reduce(UInt64(0)){$0 | UInt64($1.element) << ($1.offset*8)}}
    static func write(_ folder:URL,to destination:URL)throws {
        guard !FileManager.default.fileExists(atPath:destination.path) else{throw MainStagePatch.Failure.invalid("Choose a new pack filename; existing files are not overwritten.")}
        let pack=try LibraryBackup.read(folder),names=(Array(pack.manifest.files.keys)+["manifest.json"]).sorted()
        guard names.count<=20000 else{throw SetlistLibraryError.oversized}
        let partial=destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".partial")
        FileManager.default.createFile(atPath:partial.path,contents:nil)
        do {
            let output=try FileHandle(forWritingTo:partial);defer{try? output.close()}
            try output.write(contentsOf:magic+integer(UInt64(names.count),4))
            var total:UInt64=0
            for name in names {
                guard safe(name) else{throw SetlistLibraryError.unsafeFile}
                let file=folder.appendingPathComponent(name),values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard values.isRegularFile==true,values.isSymbolicLink != true,let size=values.fileSize,size>=0 else{throw SetlistLibraryError.unsafeFile}
                total+=UInt64(size);guard total<=byteLimit else{throw SetlistLibraryError.oversized}
                let hash=try AssetDigest.sha256(file)
                if name != "manifest.json" {guard pack.manifest.files[name]==hash else{throw CocoaError(.fileReadCorruptFile)}}
                try output.write(contentsOf:integer(UInt64(name.utf8.count),4)+integer(UInt64(size),8)+Data(hash.utf8)+Data(name.utf8))
                let input=try FileHandle(forReadingFrom:file);defer{try? input.close()}
                var remaining=size,hasher=SHA256()
                while remaining>0 {let bytes=try exact(input,min(1_048_576,remaining));try output.write(contentsOf:bytes);hasher.update(data:bytes);remaining-=bytes.count}
                guard hasher.finalize().map({String(format:"%02x",$0)}).joined()==hash else{throw CocoaError(.fileReadCorruptFile)}
            }
            try output.synchronize();try output.close();try FileManager.default.moveItem(at:partial,to:destination)
        } catch {try? FileManager.default.removeItem(at:partial);throw error}
    }
    static func unpack(_ source:URL,to folder:URL)throws->URL {
        guard !FileManager.default.fileExists(atPath:folder.path) else{throw SetlistLibraryError.unsafeFile}
        let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,let size=values.fileSize,size<=Int(byteLimit)+100_000_000 else{throw SetlistLibraryError.oversized}
        let input=try FileHandle(forReadingFrom:source);defer{try? input.close()}
        guard try exact(input,magic.count)==magic else{throw CocoaError(.fileReadCorruptFile)}
        let count=try number(input,4);guard count>0,count<=20000 else{throw SetlistLibraryError.oversized}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        do {
            var seen=Set<String>(),canonical=Set<String>(),total:UInt64=0
            for _ in 0..<count {
                let length=try number(input,4),size=try number(input,8)
                guard length>0,length<=4096,size<=byteLimit,total<=byteLimit-size else{throw SetlistLibraryError.oversized};total+=size
                let hash=String(data:try exact(input,64),encoding:.utf8)
                guard let name=String(data:try exact(input,Int(length)),encoding:.utf8),safe(name),seen.insert(name).inserted,canonical.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted,let hash,hash.count==64,hash.allSatisfy({$0.isHexDigit && !$0.isUppercase}) else{throw SetlistLibraryError.unsafeFile}
                let output=folder.appendingPathComponent(name);try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
                FileManager.default.createFile(atPath:output.path,contents:nil)
                let handle=try FileHandle(forWritingTo:output);defer{try? handle.close()}
                var remaining=size,hasher=SHA256()
                while remaining>0 {let bytes=try exact(input,Int(min(1_048_576,remaining)));try handle.write(contentsOf:bytes);hasher.update(data:bytes);remaining-=UInt64(bytes.count)}
                try handle.close()
                guard hasher.finalize().map({String(format:"%02x",$0)}).joined()==hash else{throw CocoaError(.fileReadCorruptFile)}
            }
            guard (try input.read(upToCount:1))?.isEmpty ?? true else{throw CocoaError(.fileReadCorruptFile)}
            let pack=try LibraryBackup.read(folder)
            guard seen==Set(pack.manifest.files.keys).union(["manifest.json"]) else{throw CocoaError(.fileReadCorruptFile)}
            return folder
        } catch {try? FileManager.default.removeItem(at:folder);throw error}
    }
}
