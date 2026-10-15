import Foundation
@main struct GrooveTests {
 static func main()throws {
    var program=MIDIProgram();program.kind = .arpeggiator;program.subdivision=0.5;program.swingGridBeats=0.5;program.swingAmount=1
    assert(abs(MIDIFXProcessor.groovedBeat(0.5,program:program)-2.0/3)<0.00001)
    assert(MIDIFXProcessor.groovedBeat(1,program:program)==1)
    let scheduler=MIDIFXProcessor(automaticallySchedule:false);var notes:[Int]=[]
    scheduler.onNote={_,_,note,_ in notes.append(note)};scheduler.configure(channel:0,program:program,tempo:120)
    scheduler.noteOn(channel:0,key:60,pitch:60,velocity:1);scheduler.noteOn(channel:0,key:64,pitch:64,velocity:1)
    scheduler.advance(to:0.25);assert(notes==[60]);scheduler.advance(to:0.33334);assert(notes==[60,64]);scheduler.advance(to:0.5);assert(notes==[60,64,60])
    scheduler.updateTempo(60);scheduler.advance(to:1.1);assert(notes.count==3);scheduler.advance(to:1.1667);assert(notes.last==64 && notes.count==4)
    program.swingAmount=0;assert(MIDIFXProcessor.groovedBeat(0.5,program:program)==0.5)
    program.swingGridBeats=0.25;program.swingAmount=1;assert(abs(MIDIFXProcessor.groovedBeat(0.25,program:program)-1.0/3)<0.00001)
    let decoded=try JSONDecoder().decode(MIDIProgram.self,from:JSONEncoder().encode(program));assert(decoded==program)
    program.subdivision=0.5;program.swingGridBeats=0.5;program.swingAmount=1
    for beat in stride(from:0.0,to:8.0,by:0.017) {assert(abs(MIDIFXProcessor.ungroovedBeat(MIDIFXProcessor.groovedBeat(beat,program:program),program:program)-beat)<1e-9)}
    let stalled=MIDIFXProcessor(automaticallySchedule:false);var stalledNotes:[Int]=[]
    stalled.onNote={_,_,pitch,_ in stalledNotes.append(pitch)};stalled.configure(channel:0,program:program,tempo:120);stalled.noteOn(channel:0,key:60,pitch:60,velocity:1);stalled.noteOn(channel:0,key:64,pitch:64,velocity:1)
    stalled.advance(to:0.8);assert(stalledNotes==[60,60],"Stall emitted a future swung step");stalled.advance(to:0.83334);assert(stalledNotes==[60,60,64])
    program.kind = .sequencer
    let sequence=MIDIFXProcessor(automaticallySchedule:false);var sequenceCount=0
    sequence.onNote={_,_,_,_ in sequenceCount+=1};sequence.configure(channel:0,program:program,tempo:120);sequence.noteOn(channel:0,key:60,pitch:60,velocity:1)
    sequence.advance(to:0.25);assert(sequenceCount==1);sequence.advance(to:0.33334);assert(sequenceCount==2);sequence.advance(to:0.5);assert(sequenceCount==3)
    print("PASS: swing timing, pair boundaries, tempo phase preservation, straight mode and groove persistence")
 }
}
