import Foundation
import CoreMIDI
@main struct PlugAndPlayTests {
 /// Exercises Primary/Secondary routing and learned controls through virtual CoreMIDI.
 static func main() throws {
    let store=PerformanceStore(); store.setlist=TestFixtures.setlist(); store.primarySourceID = -1; store.midiChannel = -1; store.secondarySourceID = -2
    try store.audio.prepareOffline(); store.start()
    var client=MIDIClientRef(), a=MIDIEndpointRef(), b=MIDIEndpointRef()
    assert(MIDIClientCreateWithBlock("StageKeys End to End MIDI" as CFString,&client,nil)==noErr)
    defer { if a != 0 { MIDIEndpointDispose(a) }; if b != 0 { MIDIEndpointDispose(b) }; MIDIClientDispose(client) }
    assert(MIDISourceCreate(client,"Test Keyboard A" as CFString,&a)==noErr)
    assert(MIDISourceCreate(client,"Test Keyboard B" as CFString,&b)==noErr)
    var waitIndex=0
    func wait(_ predicate:()->Bool) {
        waitIndex += 1
        let end=Date().addingTimeInterval(3)
        while !predicate() && Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
        let discovered=store.midiSources.map{String(describing:$0.endpoint)+":"+$0.name}
        assert(predicate(),"Timed out at wait \(waitIndex); endpoints \(a), \(b), discovered \(discovered), CoreMIDI source count: \(MIDIGetNumberOfSources())")
    }
    wait { store.midiSources.contains(where:{$0.name=="Test Keyboard A"}) && store.midiSources.contains(where:{$0.name=="Test Keyboard B"}) }
    store.primarySourceID=store.midiSources.first{$0.name=="Test Keyboard A"}!.id;store.midiChannel=0
    store.secondarySourceID=store.midiSources.first{$0.name=="Test Keyboard B"}!.id;store.secondaryChannel = 2
    func send(_ source:MIDIEndpointRef,_ status:UInt8,_ data1:UInt8,_ data2:UInt8) {
        var list=MIDIPacketList()
        withUnsafeMutablePointer(to:&list) { p in
            let packet=MIDIPacketListInit(p);let data:[UInt8]=[status,data1,data2]
            data.withUnsafeBufferPointer { _ = MIDIPacketListAdd(p,MemoryLayout<MIDIPacketList>.size,packet,0,3,$0.baseAddress!) }
            let result=MIDIReceived(source,p)
            assert(result==noErr,"MIDIReceived failed for \(source), status \(status): \(result)")
        }
    }
    store.velocityMinimum=32;store.velocityMaximum=96
    var receivedVelocity:Float?
    store.midiFX.onNote = { _,_,_,velocity in receivedVelocity=velocity }
    send(a,0x90,60,64);send(b,0x92,60,80);wait { store.midiLog.first?.contains("Ch 03 · 90 · 60 · 80") == true }
    send(a,0x92,65,90);send(b,0x90,66,90)
    wait { store.midiLog.first?.contains("Ch 01 · 90 · 66 · 90") == true }
    assert(store.held.count==1 && store.isNoteHeld(60),"Only the selected Primary controller and channel may generate patch notes")
    wait { receivedVelocity != nil }
    assert(abs((receivedVelocity ?? 0)-MIDIControllerRules.velocity(64,minimum:32,maximum:96))<0.0001,"Primary note velocity must use the configured range")
    var peak:Float=0
    for _ in 0..<40 { let buffer=try store.audio.offlineBlock(); for i in 0..<Int(buffer.frameLength) { peak=max(peak,abs(buffer.floatChannelData![0][i])) } }
    assert(peak > 0.01,"Hardware input must reach production audio graph")
    for _ in 0..<10 { store.midi.refresh() }; assert(store.held.count==1)
    assert(store.held.count==1,"Unselected and channel-filtered notes must not acquire note ownership")
    send(b,0x82,60,0);wait { store.midiLog.first?.contains("Ch 03 · 80 · 60 · 0") == true }
    assert(store.held.count==1 && store.isNoteHeld(60),"A Secondary note-off must not release a Primary note")
    send(a,0x80,60,0);wait { store.held.isEmpty }
    store.modWheel=0.25
    send(b,0xb2,1,127);wait { store.midiLog.first?.contains("Ch 03 · B0 · 1 · 127") == true }
    assert(abs(store.modWheel-0.25)<0.001,"Secondary CC1 must not replace the Primary fixed modulation route")
    send(b,0xb2,64,127);wait { store.midiLog.first?.contains("Ch 03 · B0 · 64 · 127") == true }
    assert(!store.sustain,"Secondary CC64 must not engage the Primary fixed sustain route")
    send(a,0xb0,1,64);wait { store.midiLog.first?.contains("Ch 01 · B0 · 1 · 64") == true }
    assert(abs(store.modWheel-Float(64)/127)<0.001,"Primary CC1 did not apply; value \(store.modWheel)")
    send(a,0xb0,64,127);wait { store.midiLog.first?.contains("Ch 01 · B0 · 64 · 127") == true }
    assert(store.sustain,"Primary CC64 was not applied; \(store.midiLog.first ?? "no monitor event")")
    send(a,0xb0,64,0);wait { !store.sustain }
    send(a,0x90,67,100);wait { store.isNoteHeld(67) }
    store.panic();assert(store.held.isEmpty)
    let beforeMacros=store.patch.layers[0]
    var macroLayer=beforeMacros
    let macroEffect=AudioEffect.factoryDefault(kind:1)
    macroLayer.importedRack=ImportedRack(effects:[macroEffect,macroEffect],macros:[
        ImportedMacro(index:0,name:"Wheel",value:0,bindings:[ImportedMacroBinding(effect:0,parameter:0,minimum:20,maximum:20000)],midiCC:1,midiChannel:0),
        ImportedMacro(index:1,name:"Pedal",value:0,bindings:[ImportedMacroBinding(effect:1,parameter:0,minimum:20,maximum:20000)],midiCC:64,midiChannel:0)
    ])
    store.commitLayer(0,macroLayer)
    send(a,0xb0,1,127)
    wait { store.patch.layers[0].importedRack?.macros[0].value==127 }
    send(a,0xb0,64,127)
    wait { store.patch.layers[0].importedRack?.macros[1].value==127 }
    send(b,0xb2,1,0);send(b,0xb2,64,0)
    wait { store.midiLog.first?.contains("Ch 03 · B0 · 64 · 0") == true }
    assert(store.patch.layers[0].importedRack?.macros.map(\.value)==[127,127],"Secondary fixed CCs must not alter imported Primary macros")
    send(a,0xb0,64,0);wait { !store.sustain }
    store.commitLayer(0,beforeMacros)
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
    store.beginMIDILearn(.master);send(b,0xb2,30,100)
    wait { store.assignedCC(.master) == 30 };assert(abs(store.master-Float(100)/127)<0.001)
    wait { store.midiLog.first?.contains("Test Keyboard B · Ch 03 · B0 · 30 · 100") == true }
    store.beginMIDILearn(.nextPatch);send(b,0xb2,31,127)
    wait { store.assignedCC(.nextPatch) == 31 };let selection=store.selected
    send(b,0xb2,31,127);RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.selected == selection)
    send(b,0xb2,31,0);send(b,0xb2,31,127);wait { store.selected == selection+1 }
    send(b,0xb2,31,127);RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.selected == selection+1)
    store.beginMIDILearn(.previousPatch);send(b,0xb2,34,127)
    wait { store.assignedCC(.previousPatch) == 34 }
    let beforePrevious=store.selected
    send(b,0xb2,34,0);send(b,0xb2,34,127);wait { store.selected == beforePrevious-1 }
    for index in 0..<5 {
        let snapshotID=store.patch.snapshots[index].id
        let cc=UInt8(40+index)
        store.beginMIDILearn(.snapshot(index));send(b,0xb2,cc,127)
        wait { store.assignedCC(.snapshot(index)) == Int(cc) }
        send(b,0xb2,cc,0);send(b,0xb2,cc,127)
        wait { store.activeSnapshot == snapshotID }
    }
    store.beginMIDILearn(.tonicLevel);send(b,0xb2,50,64)
    wait { store.assignedCC(.tonicLevel) == 50 };assert(abs(store.tonicGain-Float(64)/127)<0.001)
    store.beginMIDILearn(.tonicBrightness);send(b,0xb2,51,127)
    wait { store.assignedCC(.tonicBrightness) == 51 };assert(store.tonicBrightness==1)
    store.beginMIDILearn(.tonicShimmer);send(b,0xb2,52,64)
    wait { store.assignedCC(.tonicShimmer) == 52 };assert(abs(store.tonicShimmer-Float(64)/127)<0.001)
    var tone=AudioEffect.factoryDefault(kind:1);tone.enabled=true
    store.setEffect(0,0,tone)
    let bypass=MIDIControlTarget.effectEnabled(0,0,1)
    store.beginMIDILearn(bypass);send(b,0xb2,53,0)
    wait { store.assignedCC(bypass) == 53 };assert(!store.patch.layers[0].effects[0].enabled)
    send(b,0xb2,53,127);wait { store.patch.layers[0].effects[0].enabled }
    let frequency=MIDIControlTarget.effectParameter(0,0,1,0)
    store.beginMIDILearn(frequency);send(b,0xb2,54,127)
    wait { store.assignedCC(frequency) == 54 && store.patch.layers[0].effects[0].values[0] == 20_000 }
    store.beginMIDILearn(.sustain);send(a,0xb0,32,127);wait { store.sustain }
    store.beginMIDILearn(.modulation);send(a,0xb0,32,100)
    wait { store.assignedCC(.modulation) == 32 };assert(!store.sustain,"Rebinding a held pedal must release it")
    assert(store.message == "CC 32 moved from Sustain Pedal to Modulation Wheel.",store.message ?? "Missing rebind feedback")
    store.message = nil // Acknowledge expected feedback; later errors must still fail.
    store.beginMIDILearn(.sustain);send(a,0xb0,35,127);wait { store.sustain }
    send(a,0xb0,35,0);store.clearMIDILearn(.sustain);wait { !store.sustain }
    store.save();let learned=PerformanceStore()
    assert(learned.assignedCC(.master)==30 && learned.assignedCC(.nextPatch)==31)
    assert(learned.assignedCC(.previousPatch)==34 && (0..<5).allSatisfy{learned.assignedCC(.snapshot($0))==40+$0})
    assert(learned.assignedCC(.tonicLevel)==50 && learned.assignedCC(.tonicBrightness)==51 && learned.assignedCC(.tonicShimmer)==52)
    assert(learned.assignedCC(bypass)==53 && learned.assignedCC(frequency)==54)
    assert(learned.primarySourceID==store.primarySourceID && learned.secondarySourceID==store.secondarySourceID)
    assert(learned.midiChannel==0 && learned.secondaryChannel==2)
    assert(learned.midiSourceNames[store.primarySourceID] == "Test Keyboard A" && learned.midiSourceNames[store.secondarySourceID] == "Test Keyboard B")
    wait { learned.midiSources.contains(where:{$0.id==store.primarySourceID && $0.connected}) &&
           learned.midiSources.contains(where:{$0.id==store.secondarySourceID && $0.connected}) }
    store.setEffect(0,0,AudioEffect.factoryDefault(kind:4))
    assert(store.assignedCC(bypass)==nil && store.assignedCC(frequency)==nil,"Replacing an effect must clear mappings to controls that no longer exist")
    store.resetMIDILearn()
    assert(store.setlist.controlAssignments==nil && store.setlist.assignments.isEmpty)
    assert(store.assignedCC(.master)==nil && store.assignedCC(bypass)==nil)
    assert(store.message=="MIDI learn assignments cleared. Fixed modulation, sustain, panic and program-change routes remain.")
    store.message=nil
    store.modWheel=0.25;send(b,0xb2,1,127);assert(abs(store.modWheel-0.25)<0.001)
    store.midiLog=[];send(a,0xb0,1,127);wait { store.midiLog.first?.contains("Ch 01 · B0 · 1 · 127") == true }
    assert(store.modWheel==1)
    store.midiLog=[];send(a,0xb0,64,127);wait { store.midiLog.first?.contains("Ch 01 · B0 · 64 · 127") == true }
    assert(store.sustain,"Primary CC64 must remain active after Reset All")
    send(a,0xb0,64,0);wait { !store.sustain }
    store.setlist.patches[0].programChangeEnabled=true;store.setlist.patches[0].programChangeNumber=99
    store.choose(1);send(b,0xc2,99,0);wait { store.midiLog.first?.contains("Ch 03 · C0 · 99 · 0") == true }
    assert(store.selected==1,"Secondary Program Change must not select a patch")
    send(a,0xc0,99,0);wait {store.selected==0}
    store.setlist.patches[0].programChangeEnabled=false;store.choose(1)
    send(a,0xc0,99,0);RunLoop.current.run(until:Date().addingTimeInterval(0.1));assert(store.selected==1)
    MIDIEndpointDispose(b); b=0
    wait { store.held.isEmpty && !store.sustain }
    send(a,0x90,67,100);wait { store.isNoteHeld(67) }
    store.panic();try store.setlist.validate()
    assert(store.message == nil,store.message ?? "")
    print("PASS: Primary-only note/Program Change, filtered Primary/Secondary controls, CC1/64 ownership, velocity scaling, learned Tonic/effect/snapshot/navigation routes, assignment and source/channel persistence, hot-plug and output safety")
 }
}
