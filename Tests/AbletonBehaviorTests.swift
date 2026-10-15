import Foundation
@main struct AbletonBehaviorTests {
    static func main() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".adg")
        defer{try? FileManager.default.removeItem(at:file)}
        let xml="""
        <Ableton><GroupDevicePreset><Device><InstrumentGroupDevice><MacroControls.3><Manual Value="64"/></MacroControls.3><MacroDisplayNames.3 Value="Space"/></InstrumentGroupDevice></Device><BranchPresets><InstrumentBranchPreset><DevicePresets>
        <AbletonDevicePreset><Device><MidiPitcher><Pitch><Manual Value="12"/></Pitch><Lowest><Manual Value="0"/></Lowest><Range><Manual Value="127"/></Range></MidiPitcher></Device></AbletonDevicePreset>
        <AbletonDevicePreset><Device><MidiChord><Shift1><Manual Value="7"/></Shift1><Velocity1><Manual Value="1"/></Velocity1></MidiChord></Device></AbletonDevicePreset>
        <AbletonDevicePreset><Device><Compressor2><Threshold><Manual Value="0.5"/></Threshold><Attack><Manual Value="12"/></Attack><Ratio><Manual Value="4"/></Ratio><DryWet><Manual Value="0.75"/></DryWet></Compressor2></Device></AbletonDevicePreset>
        <AbletonDevicePreset><Device><Reverb><On><Manual Value="false"/></On><PreDelay><Manual Value="25"/></PreDelay><RoomSize><Manual Value="70"/></RoomSize><MixDirect><Manual Value="0.4"/><KeyMidi><Channel Value="16"/><NoteOrController Value="3"/></KeyMidi><MidiControllerRange><Min Value="0"/><Max Value="1"/></MidiControllerRange></MixDirect></Reverb></Device></AbletonDevicePreset>
        </DevicePresets></InstrumentBranchPreset></BranchPresets></GroupDevicePreset></Ableton>
        """
        try Data(xml.utf8).write(to:file)
        var behavior=try AbletonImport.behavior(AbletonImport.readXML(file))
        assert(behavior.rack.validate() && behavior.rack.effects.count==2)
        assert(abs(behavior.rack.effects[0].values[4] + 6.0206)<0.001)
        assert(behavior.rack.effects[0].values[1]==12 && behavior.rack.effects[0].values[3]==4)
        assert(!behavior.rack.effects[1].enabled && behavior.rack.effects[1].values[1]==25)
        assert(behavior.rack.macros.first?.name=="Space" && behavior.rack.macros.first?.bindings.count==2)
        // Saved effect values remain authoritative until the user moves the macro.
        assert(abs(behavior.rack.effects[1].values[8]-0.4)<0.001)
        behavior.rack.setMacro(3,value:127)
        assert(behavior.rack.effects[1].values[7]==0 && behavior.rack.effects[1].values[8]==1)
        behavior.rack.setMacro(3,value:0)
        assert(behavior.rack.effects[1].values[7]==1 && behavior.rack.effects[1].values[8]==0)
        let processor=MIDIFXProcessor(automaticallySchedule:false)
        var notes:[Int]=[],offs=0
        processor.onNote={_,_,pitch,_ in notes.append(pitch)};processor.onOff={_,_,_ in offs+=1}
        processor.configure(channel:0,program:behavior.midi!,tempo:120)
        processor.noteOn(channel:0,key:1,pitch:60,velocity:0.8)
        assert(notes.sorted()==[72,79]);processor.noteOff(channel:0,key:1);assert(offs==2)
        notes=[];processor.noteOn(channel:0,key:2,pitch:120,velocity:0.8);assert(notes.isEmpty)
        var layer=Layer(name:"Fixture",instrument:0,gain:0.5);layer.importedRack=behavior.rack;layer.midiProgram=behavior.midi
        let start=SnapshotSoundState(layer)
        layer.importedRack?.setMacro(3,value:127)
        let end=SnapshotSoundState(layer)
        let midpoint=SnapshotMorph.interpolateSound(from:start,to:end,fraction:0.5)
        assert(abs(midpoint.importedRack!.effects[1].values[8]-0.5)<0.001)
        assert(midpoint.importedRack!.macros[0].value==63.5)
        let decoded=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(layer));assert(decoded==layer)
        var invalid=behavior.rack;invalid.macros[0].bindings[0].effect=99;assert(!invalid.validate())
        // Parallel processing must not be incorrectly applied globally.
        try Data(xml.replacingOccurrences(of:"</BranchPresets>",with:"<InstrumentBranchPreset/></BranchPresets>").utf8).write(to:file)
        let parallel=try AbletonImport.behavior(AbletonImport.readXML(file));assert(parallel.rack.effects.isEmpty && !parallel.warnings.isEmpty)
        print("PASS: source effect values, bypass/order, linked macro ranges, pitch/chord production note lifecycle, persistence and parallel-rack safeguards")
    }
}
