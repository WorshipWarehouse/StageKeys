import Foundation
import AVFoundation

@main
struct ExternalAudioTests {
 static func main() throws {
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 48000)!
sourceBuffer.frameLength = 48000
for frame in 0..<48000 { sourceBuffer.floatChannelData![0][frame] = 0.3 * sin(Float(frame) * 2 * .pi * 261.626 / 48000) }
do {
let sourceFile = try AVAudioFile(forWriting: folder.appendingPathComponent("tone.wav"), settings: sourceFormat.settings)
try sourceFile.write(from: sourceBuffer)
}
var engine = AVAudioEngine()
var rack = try ExternalInstrumentRack(engine: engine, libraryURL: folder.appendingPathComponent("library"))
let imported = try rack.importSound(folder.appendingPathComponent("tone.wav"))
var failure: Error?
rack.load(imported, channel: 0) { if case .failure(let e) = $0 { failure = e } }
if let failure { throw failure }
assert(rack.contains(0))
try PropertyListSerialization.data(fromPropertyList: rack.state(channel: 0)!, format: .xml, options: 0).write(to: folder.appendingPathComponent("sampler-state.plist"))
let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
engine.prepare(); try engine.start()

let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
_ = try engine.renderOffline(512, to: buffer)
rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
var energy: Float = 0
for _ in 0..<30 {
 let status = try engine.renderOffline(512, to: buffer);if status != .success {FileHandle.standardOutput.write(Data("Render status \(status.rawValue)\n".utf8))}
 for frame in 0..<Int(buffer.frameLength) { energy += abs(buffer.floatChannelData![0][frame]) }
}
assert(rack.debugBuiltin(0)!.auAudioUnit.inputBusses[0].format.sampleRate == rack.debugBuiltin(0)!.auAudioUnit.outputBusses[0].format.sampleRate)

assert(energy > 0.1, "Imported sampler must produce audio")
rack.noteOff(key: 60); rack.sustain(channel: 0, on: false); rack.panic()
for slot in 0..<3 { try rack.configureEffect(channel: 0, slot: slot, kind: 9, enabled: false, parameters: [-6]) }
for _ in 0..<30 { _ = try engine.renderOffline(512, to: buffer) }
rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
var referenceEnergy: Float = 0
for _ in 0..<30 {
 _ = try engine.renderOffline(512, to: buffer)
 for frame in 0..<Int(buffer.frameLength) { referenceEnergy += abs(buffer.floatChannelData![0][frame]) }
}
rack.panic()
for slot in 0..<3 { try rack.configureEffect(channel: 0, slot: slot, kind: 9, enabled: true, parameters: [-6]) }
for _ in 0..<30 { _ = try engine.renderOffline(512, to: buffer) }
rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
var reducedEnergy: Float = 0
for _ in 0..<30 {
 _ = try engine.renderOffline(512, to: buffer)
 for frame in 0..<Int(buffer.frameLength) { reducedEnergy += abs(buffer.floatChannelData![0][frame]) }
}

assert(reducedEnergy / referenceEnergy > 0.11 && reducedEnergy / referenceEnergy < 0.15, "Three serial -6 dB slots must apply -18 dB total")
rack.panic()
assert(!ExternalInstrumentRack.supportsEffect(kind: 18))
do {
 try rack.configureEffect(channel: 0, slot: 0, kind: 16, enabled: true, parameters: [Float]())
 assertionFailure("Unsupported effects must report an error")
} catch ExternalInstrumentError.unsupportedEffect {}
print("PASS three serial gain slots: energy ratio \(reducedEnergy / referenceEnergy); unsupported effect rejected")
engine.stop()
try rack.remove(0)
assert(!rack.contains(0))
let preset = try rack.importPreset(folder.appendingPathComponent("sampler-state.plist"), sampleRoot: folder)
engine = AVAudioEngine()
rack = try ExternalInstrumentRack(engine: engine, libraryURL: folder.appendingPathComponent("library"))
rack.load(preset, channel: 1) { if case .failure(let error) = $0 { failure = error } }
if let failure { throw failure }
assert(rack.contains(1))
try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
engine.prepare(); try engine.start()
_ = try engine.renderOffline(512, to: buffer)
rack.noteOn(channel: 1, key: 60, pitch: 60, velocity: 0.8)
var presetEnergy: Float = 0
for _ in 0..<30 {
 _ = try engine.renderOffline(512, to: buffer)
 for frame in 0..<Int(buffer.frameLength) { presetEnergy += abs(buffer.floatChannelData![0][frame]) }
}
assert(presetEnergy > 0.1)
rack.panic(); engine.stop()
print("PASS sampler preset sample references copied/relinked and rendered: \(presetEnergy)")

// Use the locally installed Apple GM bank only; never include it in deliverables.
let appleBank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
if FileManager.default.fileExists(atPath: appleBank.path) {
 engine = AVAudioEngine()
 rack = try ExternalInstrumentRack(engine: engine, libraryURL: folder.appendingPathComponent("bank-library"))
 let bank = try rack.importSound(appleBank)
 rack.load(bank, channel: 0) { if case .failure(let error) = $0 { failure = error } }
 if let failure { throw failure }
 try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
 engine.prepare(); try engine.start()
 _ = try engine.renderOffline(512, to: buffer)
 rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
 var bankEnergy: Float = 0
 for _ in 0..<30 {
  _ = try engine.renderOffline(512, to: buffer)
  for frame in 0..<Int(buffer.frameLength) { bankEnergy += abs(buffer.floatChannelData![0][frame]) }
 }
 assert(bankEnergy > 0.1, "Installed Apple DLS piano must render")
 for kind in 1...15 {
  var controls: [String: Float] = ["Tempo": 120]
  let defaults = AudioEffectCatalog.defaults(for: kind)
  for descriptor in AudioEffectCatalog.descriptors(for: kind) { controls[descriptor.name] = defaults[descriptor.index] }
  try rack.configureEffect(channel: 0, slot: 0, kind: kind, enabled: true, parameters: controls)
  rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
  for _ in 0..<10 {
   _ = try engine.renderOffline(512, to: buffer)
   for frame in 0..<Int(buffer.frameLength) { assert(buffer.floatChannelData![0][frame].isFinite) }
  }
  rack.panic()
 }
 print("PASS every supported native FX kind changes while running and renders finite output")
 rack.panic(); engine.stop()
 print("PASS installed Apple DLS sound-bank program renders: \(bankEnergy)")
}
let components = ExternalInstrumentRack.instruments()
assert(!components.isEmpty)
print("PASS imported WAV renders audio; notes/sustain/panic/removal; \(components.count) installed AU instruments discovered. Energy: \(energy)")

 }
}
