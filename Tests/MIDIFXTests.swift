import Foundation
@main struct MIDIFXTests {
 static func main() throws {
  let p = MIDIFXProcessor(automaticallySchedule: false)
  var notes: [(Int,Int,Int,Float)] = []; var offs: [(Int,Int,Bool)] = []
  p.onNote = { notes.append(($0,$1,$2,$3)) }; p.onOff = { offs.append(($0,$1,$2)) }
  p.noteOn(channel: 0,key: 60,pitch: 60,velocity: 1)
  p.noteOn(channel: 1,key: 60,pitch: 60,velocity: 1)
  p.noteOff(channel: 0,key: 60)
  assert(offs.count == 1 && offs[0].0 == 0 && offs[0].1 == 60)
  p.panic(); assert(offs.last!.0 == 1)
  var program = MIDIProgram(); program.kind = .easyChord
  p.configure(channel: 0,program: program,tempo: 120)
  p.noteOn(channel: 0,key: 60,pitch: 60,velocity: 0.7)
  assert(Array(notes.suffix(3)).map { $0.2 } == [60,64,67])
  assert(notes.suffix(3).allSatisfy { $0.1 < 0 })
  p.noteOff(channel: 0,key: 60);assert(offs.suffix(3).allSatisfy { !$0.2 })
  program.kind = .arpeggiator; program.subdivision = 0.5; program.gate = 0.5
  p.configure(channel: 0,program: program,tempo: 120)
  p.noteOn(channel: 0,key: 60,pitch: 60,velocity: 1)
  let first = notes.last!;p.advance(to: 0.125)
  assert(offs.last!.1 == first.1 && offs.last!.2)
  p.noteOn(channel: 0,key: 64,pitch: 64,velocity: 1)
  p.advance(to: 0.25); assert(notes.last!.2 == 64)
  p.advance(to: 0.5); assert(notes.last!.2 == 60)
  let count = notes.count;p.panic();p.advance(to: 100);assert(notes.count == count)
  program.kind = .sequencer;program.steps = [.init(pitch: 0,velocity: 0.5),.init(pitch: 12,velocity: 0.25),.init(enabled: false)]
  p.configure(channel: 0,program: program,tempo: 120)
  p.noteOn(channel: 0,key: 48,pitch: 48,velocity: 0.8)
  assert(notes.last!.2 == 48 && abs(notes.last!.3 - 0.4) < 0.001)
  p.advance(to: 100.25);assert(notes.last!.2 == 60)
  let before = notes.count;p.advance(to: 100.5);assert(notes.count == before)
  p.configure(channel: 0,program: MIDIProgram(),tempo: 120)
  assert(offs.last!.2)
  var arp=MIDIProgram();arp.kind = .arpeggiator;arp.style = .upDown
  let pitches=(0..<8).map { MIDIFXProcessor.arpeggio(held: [(60,1),(64,1),(67,1)],program: arp,index: $0)!.0 }
  assert(pitches == [60,64,67,64,60,64,67,64])
  let encoded=try JSONEncoder().encode(program);let decoded = try JSONDecoder().decode(MIDIProgram.self,from: encoded);assert(decoded == program)
  // New optional fields retain nil on legacy configuration and decoded v3 files.
  let legacy = MIDIProgram().validated
  assert(legacy.octaveBlend == nil && legacy.arpVelocities == nil && legacy.chordMappings == nil && legacy.sequenceMappings == nil && legacy.sequenceVelocity == nil)
  let legacyJSON = "{\"kind\":\"bypass\",\"subdivision\":0.25,\"gate\":0.8,\"style\":\"up\",\"octaves\":1,\"chordIntervals\":[0,4,7],\"steps\":[{\"pitch\":0,\"velocity\":1,\"enabled\":true}]}".data(using: .utf8)!
  let old = try JSONDecoder().decode(MIDIProgram.self, from: legacyJSON)
  assert(old.validated.octaveBlend == nil)
  arp.style = .downUp
  assert((0..<8).map { MIDIFXProcessor.arpeggio(held: [(60,1),(64,1),(67,1)],program: arp,index: $0)!.0 } == [67,64,60,64,67,64,60,64])
  arp.style = .random
  let random = (0..<40).map { MIDIFXProcessor.arpeggio(held: [(60,1),(64,1),(67,1)],program: arp,index: $0)!.0 }
  assert(Set(random).count == 3)
  assert(random == (0..<40).map { MIDIFXProcessor.arpeggio(held: [(60,1),(64,1),(67,1)],program: arp,index: $0)!.0 })
  let q = MIDIFXProcessor(automaticallySchedule: false)
  var qNotes: [(Int,Int,Int,Float)] = []; var qOff: [(Int,Int,Bool)] = []
  q.onNote = { qNotes.append(($0,$1,$2,$3)) }; q.onOff = { qOff.append(($0,$1,$2)) }
  var modern = MIDIProgram(); modern.kind = .octaveUp; modern.octaveBlend = 0.25
  q.configure(channel: 2,program: modern,tempo: 120);q.noteOn(channel: 2,key: 60,pitch: 60,velocity: 0.8)
  assert(qNotes.map { $0.2 } == [60,72] && abs(qNotes.last!.3 - 0.2) < 0.001)
  q.noteOff(channel: 2,key: 60);assert(qOff.count == 2)
  modern.kind = .easyChord;modern.chordMappings = [.init(input: 60,output: [48,55,64]),.init(input: 61,output: [])]
  q.configure(channel: 2,program: modern,tempo: 120);let c0 = qNotes.count
  q.noteOn(channel: 2,key: 60,pitch: 60,velocity: 1)
  assert(qNotes.suffix(3).map { $0.2 } == [48,55,64])
  q.noteOn(channel: 2,key: 61,pitch: 61,velocity: 1);assert(qNotes.count == c0 + 3)
  q.noteOn(channel: 2,key: 62,pitch: 62,velocity: 1);assert(qNotes.last!.2 == 62)
  q.panic()
  modern.kind = .arpeggiator;modern.style = .chord;modern.arpVelocities = [0.5,0,1];modern.subdivision = 0.5
  q.configure(channel: 2,program: modern,tempo: 120)
  q.noteOn(channel: 2,key: 60,pitch: 60,velocity: 1);q.noteOn(channel: 2,key: 64,pitch: 64,velocity: 1)
  assert(qNotes.last!.3 == 0.5)
  let c1=qNotes.count;q.advance(to: 0.25);assert(qNotes.count == c1)
  q.advance(to: 0.5);assert(qNotes.suffix(2).map { $0.2 } == [60,64])
  let sourceKey=qNotes[qNotes.count-2].1;q.noteOff(channel: 2,key: 60)
  assert(qOff.last!.1 == sourceKey && qOff.last!.2)
  q.panic()
  modern.kind = .sequencer;modern.sequenceVelocity = 0.5
  modern.sequenceMappings = [.init(input: 60,steps: [.init(pitch: 36,velocity: 0.4),.init(pitch: 38,enabled: false)]),.init(input: 64,steps: [.init(pitch: 72),.init(pitch: 74)])]
  q.configure(channel: 2,program: modern,tempo: 120)
  q.noteOn(channel: 2,key: 60,pitch: 60,velocity: 1)
  assert(qNotes.last!.2 == 36 && abs(qNotes.last!.3 - 0.2) < 0.001)
  q.noteOn(channel: 2,key: 64,pitch: 64,velocity: 1)
  q.advance(to: 0.75);assert(qNotes.last!.2 == 74)
  q.advance(to: 1);assert(qNotes.suffix(2).map { $0.2 } == [36,72])
  let mappedSourceKey = qNotes[qNotes.count-2].1
  q.noteOff(channel: 2,key: 60);assert(qOff.last!.1 == mappedSourceKey)
  q.panic();let stopped = qNotes.count;q.advance(to: 20);assert(qNotes.count == stopped)
  modern.arpVelocities = Array(repeating: 2,count: 200);modern.steps = Array(repeating: .init(),count: 200)
  modern.sequenceMappings = [.init(input: 300,steps: Array(repeating: .init(pitch: 300),count: 200))]
  assert(modern.validated.arpVelocities!.count == 128 && modern.validated.arpVelocities![0] == 1)
  assert(modern.validated.steps.count == 128 && modern.validated.sequenceMappings![0].steps.count == 128)
  assert(modern.validated.sequenceMappings![0].input == 127 && modern.validated.sequenceMappings![0].steps[0].pitch == 127)
  print("PASS: MIDI FX routing, chords, arp, gate, sequence velocity/rest, panic, reconfigure, Codable")
 }
}
