import Foundation
@main struct AbletonTimingTests {
    static func main()throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".adg");defer{try? FileManager.default.removeItem(at:file)}
        func behavior(_ devices:String)throws->AbletonImport.Behavior {
            let xml="<Ableton><GroupDevicePreset><Device><InstrumentGroupDevice/></Device><BranchPresets><InstrumentBranchPreset><DevicePresets>"+devices+"</DevicePresets></InstrumentBranchPreset></BranchPresets></GroupDevicePreset></Ableton>"
            try Data(xml.utf8).write(to:file);return try AbletonImport.behavior(AbletonImport.readXML(file))
        }
        func device(_ tag:String,_ params:String)->String {"<AbletonDevicePreset><Device><\(tag)>\(params)</\(tag)></Device></AbletonDevicePreset>"}
        func parameter(_ name:String,_ value:String)->String {"<\(name)><Manual Value=\"\(value)\"/></\(name)>"}
        let delay=try behavior(device("CrossDelay",parameter("BeatDelayEnumL","3")+parameter("BeatDelayEnumR","2")+parameter("NoteOffsetLeft","25")+parameter("Feedback","0.4")+parameter("DryWet","0.6")))
        let timing=delay.rack.effects[0].importedDelay!
        assert(timing.left==1.25 && timing.right==0.75 && timing.leftSynced && timing.rightSynced)
        assert(abs(timing.seconds(timing.left,synced:true,tempo:120)-0.625)<0.001)
        assert(delay.rack.validate())
        let modern=try behavior(device("Delay",parameter("DelayLine_SyncL","true")+parameter("DelayLine_SyncR","false")+parameter("DelayLine_SyncedSixteenthL","2")+parameter("DelayLine_TimeR","0.375")+parameter("Feedback","0.35")+parameter("DryWet","0.15")))
        assert(modern.rack.effects[0].importedDelay?.left==0.75 && modern.rack.effects[0].importedDelay?.right==0.375 && modern.rack.effects[0].importedDelay?.rightSynced==false)
        assert(abs(modern.rack.effects[0].values[3]-0.15)<0.001 && modern.rack.validate())
        let free=try behavior(device("CrossDelay",parameter("SyncModeLeft","false")+parameter("MsDelayLeft","275")+parameter("Linked","true")))
        assert(free.rack.effects[0].importedDelay!.left==0.275 && free.rack.effects[0].importedDelay!.right==0.275)
        let nested="<GroupDevicePreset><Device><AudioEffectGroupDevice/></Device><BranchPresets><AudioEffectBranchPreset><DevicePresets>"+device("CrossDelay","")+device("Reverb","")+"</DevicePresets></AudioEffectBranchPreset></BranchPresets></GroupDevicePreset>"
        let gainMacro="<Gain><Manual Value=\"1\"/><KeyMidi><Channel Value=\"16\"/><NoteOrController Value=\"0\"/></KeyMidi><MidiControllerRange><Min Value=\"0.001\"/><Max Value=\"1\"/></MidiControllerRange></Gain>"
        let audioBranch="<AudioEffectBranchPreset><Name Value=\"Dry\"/><DevicePresets>"+device("StereoGain",gainMacro)+"</DevicePresets></AudioEffectBranchPreset>"
        let split="<GroupDevicePreset><Device><AudioEffectGroupDevice><MacroDisplayNames.0 Value=\"Blend\"/><MacroControls.0><Manual Value=\"127\"/></MacroControls.0></AudioEffectGroupDevice></Device><BranchPresets>"+audioBranch+audioBranch+"</BranchPresets></GroupDevicePreset>"
        let parallel=try behavior(device("StereoGain",parameter("Gain","1"))+split+device("StereoGain",parameter("Gain","0.5")))
        assert(parallel.rack.effects.count==2 && parallel.rack.audioRacks?.first?.beforeEffect==1)
        assert(parallel.rack.audioRacks?.first?.branches.count==2 && parallel.rack.validate())
        assert(parallel.rack.macros.count==1 && parallel.rack.macros[0].bindings.map{$0.audioPath!}==[[0,0],[0,1]])
        var changed=parallel.rack;changed.setMacro(changed.macros[0].index,value:0);assert(abs(changed.audioRacks![0].branches[0].rack.effects[0].values[0]+60)<0.001)
        let serial=try behavior(device("FilterEQ3","")+nested+device("Compressor2",""))
        assert(serial.rack.effects.map(\.kind)==[7,3,13,6],"Nested serial device order changed")
        let arp=try behavior(device("MidiArpeggiator",parameter("Mode","0")+parameter("SyncedRate","8")+parameter("Gate","118")+parameter("Hold","true")))
        let program=arp.midi!;assert(program.subdivision==0.5 && program.gate==1.18 && program.hold==true)
        let processor=MIDIFXProcessor(automaticallySchedule:false);var notes:[Int]=[],offs:[Bool]=[]
        processor.onNote={_,_,pitch,_ in notes.append(pitch)};processor.onOff={_,_,force in offs.append(force)}
        processor.configure(channel:0,program:program,tempo:120)
        for key in [60,64,67]{processor.noteOn(channel:0,key:key,pitch:key,velocity:1)}
        processor.advance(to:0.25);assert(notes==[60,64]);assert(offs.isEmpty,"Overlapping gate cut early")
        processor.advance(to:0.3);assert(offs==[false])
        for key in [60,64,67]{processor.noteOff(channel:0,key:key)}
        processor.advance(to:0.5);assert(notes.last==67,"Hold stopped at physical key-up")
        for key in [60,64,67]{processor.noteOff(channel:0,key:key,force:true)}
        let count=notes.count;processor.advance(to:1);assert(notes.count==count,"Disconnect did not clear held arp")
        let held=MIDIFXProcessor(automaticallySchedule:false);var sourceNotes:[Int]=[]
        held.onNote={_,_,note,_ in sourceNotes.append(note)};held.configure(channel:0,program:program,tempo:120)
        held.noteOn(channel:0,key:1,pitch:60,velocity:1,sourceID:101);held.noteOff(channel:0,key:1)
        held.releaseSource(101);let unplugged=sourceNotes.count;held.advance(to:1);assert(sourceNotes.count==unplugged,"Released Hold notes survived unplug")
        held.noteOn(channel:0,key:2,pitch:64,velocity:1,sourceID:202);held.noteOff(channel:0,key:2)
        held.releaseSource(101);held.advance(to:1.25);assert(sourceNotes.last==64,"Unplug silenced a different source")
        held.panic()
        var p=MIDIProgram();p.kind = .arpeggiator;p.freeRateSeconds=0.02;p.repeatCount=1
        let repeats=MIDIFXProcessor(automaticallySchedule:false);var repeated=0;repeats.onNote={_,_,_,_ in repeated+=1};repeats.configure(channel:0,program:p,tempo:72);repeats.noteOn(channel:0,key:60,pitch:60,velocity:1);repeats.advance(to:0.02);assert(repeated==1)
        p.repeatCount=nil;p.freeRateSeconds=nil;p.subdivision=0.25;p.velocityTarget=0.25;p.velocityDecaySeconds=0.25
        let slope=MIDIFXProcessor(automaticallySchedule:false);var velocities:[Float]=[];slope.onNote={_,_,_,v in velocities.append(v)};slope.configure(channel:0,program:p,tempo:120);slope.noteOn(channel:0,key:60,pitch:60,velocity:1);slope.advance(to:0.125);slope.advance(to:0.25)
        assert(velocities.count==3 && abs(velocities[1]-0.625)<0.001 && velocities[2]==0.25)
        let decoded=try JSONDecoder().decode(ImportedRack.self,from:JSONEncoder().encode(serial.rack));assert(decoded==serial.rack)
        print("PASS: saved stereo/free delay times, nested audio rack order, arp rate/gate/hold, forced release, finite repeats, velocity slope and persistence")
    }
}
