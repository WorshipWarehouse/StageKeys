import Foundation

/// Optional sound pack. The application has no build/runtime dependency on a pack.
enum LibraryBackup {
    struct Manifest:Decodable {var format:String;var version:Int;var files:[String:String]}
    struct Pack {var root:URL;var manifest:Manifest;var sounds:[LibrarySound]}
    static let token="@STAGEKEYS_LIBRARY@"
    static func read(_ folder:URL)throws->Pack {
        let root=folder.resolvingSymlinksInPath().standardizedFileURL
        let file=root.appendingPathComponent("manifest.json")
        guard let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=2_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:file))
        guard manifest.format=="stagekeys-private-library",manifest.version==1,manifest.files.count<=20000 else{throw ExternalInstrumentError.unsupportedFormat}
        let catalog=try asset("sound-library.json",in:root,manifest:manifest)
        let data=try Data(contentsOf:catalog);guard data.count<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let sounds=try JSONDecoder().decode([LibrarySound].self,from:data).filter{$0.sound != nil || $0.layer != nil}
        try SoundLibrary.validate(sounds)
        return Pack(root:root,manifest:manifest,sounds:sounds)
    }
    static func asset(_ relative:String,in root:URL,manifest:Manifest)throws->URL {
        guard !relative.hasPrefix("/"),!relative.split(separator:"/").contains(".."),let expected=manifest.files[relative],expected.count==64,expected.allSatisfy({$0.isHexDigit}) else{throw MainStagePatch.Failure.invalid("Unsafe or unlisted library asset.")}
        let file=root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path+"/"),try AbletonArchive.sha256(file)==expected else{throw MainStagePatch.Failure.invalid("Library asset is missing or changed: "+relative+". Download Git LFS assets before importing.")}
        return file
    }
    static func preset(_ sound:ExternalSound,pack:Pack,to output:URL)throws {
        guard sound.kind == .samplerPreset,let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent else{throw ExternalInstrumentError.unsupportedFormat}
        let source=try asset("Imported Sounds/"+name,in:pack.root,manifest:pack.manifest)
        let data=try Data(contentsOf:source);guard data.count<=16_000_000,var state=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any],let refs=state["file-references"] as? [String:String] else{throw ExternalInstrumentError.unsupportedFormat}
        var relocated:[String:String]=[:]
        for (key,path) in refs {
            guard path.hasPrefix(token+"/") else{throw MainStagePatch.Failure.invalid("Pack samples must use portable library references.")}
            relocated[key]=try asset(String(path.dropFirst(token.count+1)),in:pack.root,manifest:pack.manifest).path
        }
        state["file-references"]=relocated
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:output,options:.atomic)
    }
}
