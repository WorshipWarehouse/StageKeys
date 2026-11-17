// Local-only audit. Compile against the testable verification core; see
// Docs/NORD-NATIVE-VALIDATION.md. Never upload its output directory or audio.
@testable import StageKeysVerificationCore
import Foundation
import AVFoundation
import CryptoKit
import Darwin
@main struct NordPrivateAudit {
 @MainActor static func main() async throws {
  guard CommandLine.arguments.count>=4 else{fatalError("Usage: nord-audit NEW-OUTPUT-DIRECTORY piano1.npno piano2.npno")}
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),manager=FileManager.default
  guard !manager.fileExists(atPath:root.path) else{fatalError("Output must be a new directory; never point this at your normal app data")}
  try manager.createDirectory(at:root,withIntermediateDirectories:true)
  setenv("STAGEKEYS_DATA_DIR",root.path,1)
  let store=PerformanceStore()
  var reports:[[String:Any]]=[]
  for path in CommandLine.arguments.dropFirst(2) {
   let source=URL(fileURLWithPath:path),hashBefore=try AssetDigest.sha256(source)
   let start=Date(),bytes=try NordPiano.read(source),index=try NordPiano.index(bytes)
   var hash=SHA256(),frames=0,peak=0
   let decodeStart=Date()
   for stroke in index.strokes {
    let pcm=try NordPiano.decode(bytes,stroke:stroke,channels:index.report.channels)
    pcm.withUnsafeBytes{hash.update(bufferPointer:$0)}
    frames+=pcm.count/index.report.channels
    peak=max(peak,pcm.map{abs(Int($0))}.max() ?? 0)
   }
   let decodeSeconds=Date().timeIntervalSince(decodeStart)
   let digest=hash.finalize().map{String(format:"%02x",$0)}.joined()
   for stroke in index.strokes where stroke.root==60 && stroke.bank==0 {
    let a=try NordPiano.decode(bytes,stroke:stroke,channels:index.report.channels)
    let b=try NordPiano.decode(bytes,stroke:stroke,channels:index.report.channels)
    guard a==b else{fatalError("Nonrepeatable middle-C PCM")}
   }
   func wait() async throws {
    for _ in 0..<30000 where store.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
    guard !store.libraryImportBusy else{fatalError("Import exceeded five minutes")}
   }
   let importStart=Date()
   store.inspectNordSound(source);try await wait()
   guard let preview=store.nordImportPreview else{fatalError(store.libraryImportProgress ?? "No preview")}
   store.importNordSound();try await wait()
   guard let entry=store.librarySounds.first(where:{$0.id==preview.identity}),let layer=entry.layer else{fatalError(store.libraryImportProgress ?? "Import failed")}
   let importSeconds=Date().timeIntervalSince(importStart)
   let renderStart=Date()
   let rendering: [[String:Any]] = try autoreleasepool {
    let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
    audio.configure(0,layer);audio.gain(0,layer.gain,seconds:0);audio.master(0.1);audio.space(0)
    for _ in 0..<20 {_ = try audio.offlineBlock()}
    var captures:[[String:Any]]=[]
    for key in [36,60,96] {
     for velocity in [20,57,58,100,127] {
      audio.noteOn(key:key,pitch:key,instrument:-1,layer:0,velocity:Float(velocity)/127)
      var energy=[0.0,0.0],peak=0.0
      for _ in 0..<90 {
       let b=try audio.offlineBlock()
       for c in 0..<Int(b.format.channelCount) {for f in 0..<Int(b.frameLength) {
        let v=Double(b.floatChannelData![c][f]);guard v.isFinite else{fatalError("Nonfinite native output")}
        energy[c]+=v*v;peak=max(peak,abs(v))
       }}
      }
      audio.noteOff(key:key,channel:0)
      for _ in 0..<20 {_ = try audio.offlineBlock()}
      guard energy.reduce(0,+)>0.00001 else{fatalError("Silent native output at \(key)/\(velocity)")}
      captures.append(["key":key,"velocity":velocity,"energy":energy,"peak":peak])
     }
    }
    return captures
   }
   guard try AssetDigest.sha256(source)==hashBefore else{fatalError("Source changed")}
   let banks=Dictionary(grouping:index.strokes,by:{$0.bank}).map { (String($0.key),$0.value.count) }
   reports.append(["source":source.lastPathComponent,"sourceSHA256":hashBefore,"sourceBytes":bytes.count,
     "channels":index.report.channels,"strokes":index.strokes.count,"banks":Dictionary(uniqueKeysWithValues:banks),
     "decodedFrames":frames,"decodedBytes":index.decodedBytes,"decodedPeak":peak,"pcmSHA256NativeEndian":digest,
     "allStrokeDecodeSeconds":decodeSeconds,"importSeconds":importSeconds,"totalSeconds":Date().timeIntervalSince(start),
     "offlineRenderSeconds":Date().timeIntervalSince(renderStart),"renderCases":rendering,"mappedZones":preview.zones.count,
     "convertedPCMBytes":preview.pcmBytes,"differences":preview.notes])
   print("PASS private decode/import/native offline render:",source.lastPathComponent)
  }
  var usage=rusage();getrusage(RUSAGE_SELF,&usage)
  let result:[String:Any]=["os":ProcessInfo.processInfo.operatingSystemVersionString,"sampleRate":48000,"blockFrames":512,
    "mode":"offline native StageKeys rack; no hardware latency, listening or physical iPad claim", "peakRSSBytes":usage.ru_maxrss,"reports":reports]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("report.json"),options:.atomic)
 }
}
