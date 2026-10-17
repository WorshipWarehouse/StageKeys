import Foundation
import AVFoundation
@main struct AudioDiagnosticRecorderTests {
 static func main()throws {
  let folder=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("audio-check",isDirectory:true)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,url=folder.appendingPathComponent("check.wav")
  var outcome:Result<AudioDiagnosticRecorder.Summary,Error>?,callbacks=0
  let recorder=try AudioDiagnosticRecorder(url:url,format:format,seconds:0.005){outcome=$0;callbacks+=1}
  for block in 0..<3 {
   let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:128)!;buffer.frameLength=128
   for i in 0..<128 {buffer.floatChannelData![0][i]=Float(block*128+i)/1000;buffer.floatChannelData![1][i] = -Float(block*128+i)/2000}
   recorder.append(buffer)
  }
  recorder.finish();recorder.finish()
  let deadline=Date().addingTimeInterval(5)
  while outcome==nil && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
  guard let outcome else{fatalError("Audio check did not finish")}
  let summary=try outcome.get();assert(summary.frames==240 && callbacks==1 && summary.sampleRate==48000)
  let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
  assert(file.length==240 && file.processingFormat.channelCount==2)
  let result=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:240)!;try file.read(into:result)
  for i in 0..<240 {assert(abs(result.floatChannelData![0][i]-Float(i)/1000)<1e-7);assert(abs(result.floatChannelData![1][i]+Float(i)/2000)<1e-7)}
  do{_ = try AudioDiagnosticRecorder(url:folder.appendingPathComponent("bad.wav"),format:format,seconds:0){_ in};fatalError("Invalid duration accepted")}catch{}
  print("PASS: bounded stereo output capture preserves sample order, engine rate and float samples; exact duration and idempotent stop")
 }
}
