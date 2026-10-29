import Foundation
import CoreMIDI
@main struct PlugAndPlayTests {
 static func main() throws {
    let store=PerformanceStore(); store.setlist=TestFixtures.setlist(); store.primarySourceID = -1; store.midiChannel = -1; store.secondarySourceID = -2
    try store.audio.prepareOffline(); store.start()
    var client=MIDIClientRef(), a=MIDIEndpointRef(), b=MIDIEndpointRef()
    assert(MIDIClientCreateWithBlock("StageKeys End to End MIDI" as CFString,&client,nil)==noErr)
    defer { if a != 0 { MIDIEndpointDispose(a) }; if b != 0 { MIDIEndpointDispose(b) }; MIDIClientDispose(client) }
    assert(MIDISourceCreate(client,"Test Keyboard A" as CFString,&a)==noErr)
    assert(MIDISourceCreate(client,"Test Keyboard B" as CFString,&b)==noErr)
    func wait(_ predicate:()->Bool) { let end=Date().addingTimeInterval(3); while !predicate() && Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }; assert(predicate()) }
    wait { store.midiSources.contains(where:{$0.endpoint==a}) && store.midiSources.contains(where:{$0.endpoint==b}) }
    store.primarySourceID=store.midiSources.first{$0.endpoint==a}!.id
    store.secondarySourceID=store.midiSources.first{$0.endpoint==b}!.id;store.secondaryChannel = -1
    func send(_ source:MIDIEndpointRef,_ status:UInt8,_ data1:UInt8,_ data2:UInt8) {
        var list=MIDIPacketList()
        withUnsafeMutablePointer(to:&list) { p in
            let packet=MIDIPacketListInit(p);let data:[UInt8]=[status,data1,data2]
            data.withUnsafeBufferPointer { _ = MIDIPacketListAdd(p,MemoryLayout<MIDIPacketList>.size,packet,0,3,$0.baseAddress!) }
            assert(MIDIReceived(source,p)==noErr)
        }
    }
    send(a,0x90,60,100);send(b,0x92,60,80)
    wait { store.held.count==2 && store.isNoteHeld(60) }
    var peak:Float=0
    for _ in 0..<40 { let buffer=try store.audio.offlineBlock(); for i in 0..<Int(buffer.frameLength) { peak=max(peak,abs(buffer.floatChannelData![0][i])) } }
    assert(peak > 0.01,"Hardware input must reach production audio graph")
    for _ in 0..<10 { store.midi.refresh() }; assert(store.held.count==2)
    send(a,0x80,60,0);wait { store.held.count==1 };assert(store.isNoteHeld(60))
    send(b,0xb2,64,127);wait { store.sustain }
    MIDIEndpointDispose(b); b=0
    wait { store.held.isEmpty && !store.sustain }
    send(a,0x90,67,100);wait { store.isNoteHeld(67) }
    store.panic();assert(store.held.isEmpty)
    var fx=AudioEffect();fx.kind=3;fx.parameters=AudioEffectCatalog.defaults(for:3);fx.parameters![0]=0.65
    store.setEffect(0,0,fx);store.modWheel=0.3;store.captureSnapshot(0)
    let scene=store.patch.snapshots[0]
    fx.parameters![0]=0.1;store.setEffect(0,0,fx);store.modWheel=0.9
    store.transition = 0.1
    store.recall(scene)
    assert(store.patch.layers[0].effects[0].parameters![0] == 0.1 && abs(store.modWheel - 0.9) < 0.001)
    wait { store.patch.layers[0].effects[0].parameters![0] == 0.65 }
    assert(store.patch.layers[0].effects[0].parameters![0]==0.65 && abs(store.modWheel-0.3)<0.001)
    var crusher=AudioEffect();crusher.kind=4;crusher.parameters=AudioEffectCatalog.defaults(for:4)
    store.setEffect(0,0,crusher)
    assert(store.patch.snapshots.allSatisfy { $0.sounds?[0].effects[0].kind==4 })
    store.panic()
    var transposed=store.patch.layers[0]
    transposed.transpose=12; transposed.midiProgram=MIDIProgram(kind:.easyChord)
    transposed.midiProgram!.chordMappings=[MIDIChordMapping(input:72,output:[75])]
    store.commitLayer(0,transposed)
    var routed:[Int]=[]
    store.midiFX.onNote = { channel, _, pitch, _ in if channel == 0 { routed.append(pitch) } }
    store.noteOn(60); assert(routed == [75],"Input transpose must precede chord lookup")
    store.noteOff(60); routed=[]
    send(a,0x90,60,100);wait { routed == [75] }
    send(a,0x80,60,0);wait { store.held.isEmpty }
    store.beginMIDILearn(.master);send(a,0xb0,30,100)
    wait { store.assignedCC(.master) == 30 };assert(abs(store.master-Float(100)/127)<0.001)
    store.beginMIDILearn(.nextPatch);send(a,0xb0,31,127)
    wait { store.assignedCC(.nextPatch) == 31 };let selection=store.selected
    send(a,0xb0,31,127);RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.selected == selection)
    send(a,0xb0,31,0);send(a,0xb0,31,127);wait { store.selected == selection+1 }
    send(a,0xb0,31,127);RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.selected == selection+1)
    store.beginMIDILearn(.sustain);send(a,0xb0,32,127);wait { store.sustain }
    store.beginMIDILearn(.modulation);send(a,0xb0,32,100)
    wait { store.assignedCC(.modulation) == 32 };assert(!store.sustain,"Rebinding a held pedal must release it")
    assert(store.message == "CC 32 moved from Sustain Pedal to Modulation Wheel.",store.message ?? "Missing rebind feedback")
    store.message = nil // Acknowledge expected feedback; later errors must still fail.
    store.beginMIDILearn(.sustain);send(a,0xb0,33,127);wait { store.sustain }
    send(a,0xb0,64,127);store.clearMIDILearn(.sustain)
    RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.sustain)
    send(a,0xb0,64,0);wait { !store.sustain }
    store.save();let learned=PerformanceStore();assert(learned.assignedCC(.master)==30 && learned.assignedCC(.nextPatch)==31)
    store.setlist.patches[0].programChangeEnabled=true;store.setlist.patches[0].programChangeNumber=99
    send(a,0xc0,99,0);wait {store.selected==0}
    store.setlist.patches[0].programChangeEnabled=false;store.choose(1)
    send(a,0xc0,99,0);RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.selected==1)
    store.panic();try store.setlist.validate()
    assert(store.message == nil,store.message ?? "")
    print("PASS: CoreMIDI hot-plug → source-aware production Store → audible graph; simultaneous notes, sustain/unplug, stable refresh, FX/mod snapshot recall and effect replacement")
 }
}
