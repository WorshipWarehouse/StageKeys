import Foundation
@main struct MainStageEffectSelectionTests {
    static func main()throws {
        func device(_ name:String,_ values:[Float])->Data {
            let size=208+values.count*4
            var data=Data(repeating:0,count:size+36)
            data.replaceSubrange(0..<4,with:Data("UCuA".utf8))
            for i in 0..<4{data[28+i]=UInt8((size >> (i*8)) & 255)}
            data.replaceSubrange(156..<156+name.utf8.count,with:Data(name.utf8))
            data.replaceSubrange(168..<172,with:Data("GAME".utf8));data.replaceSubrange(220..<228,with:Data("GAMETSPP".utf8))
            for (index,value) in values.enumerated(){for i in 0..<4{data[236+index*4+i]=UInt8((value.bitPattern >> (i*8)) & 255)}}
            return data
        }
        var source=Data(repeating:0,count:36);source.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        source.append(device("Gain",[-6,0,0,0,0,0,0]))
        var eq:[Float]=[]
        for band in 0..<8{eq += [1,Float([79,198,265,630,1000,1900,4800,11000][band]),band==0 || band==7 ? 3:-2,0.707]}
        source.append(device("Chan EQ",eq))
        var comp=[Float](repeating:0,count:25)
        comp[0] = -38;comp[1]=12;comp[2]=10;comp[3]=370;comp[4]=8.5;comp[24]=75
        source.append(device("Comp",comp))
        source.append(device("Chorus",[0.5,0.4,0.3]))
        var bypassedClip=device("ClipDist",[13.5,730,0,28,2000,20000,7,20,0,0]);bypassedClip[148]=1
        source.append(bypassedClip)
        source.append(device("Chorus",[1.2,0.2,0.5]))
        let row:[String:Any]=["slot":0,"parameterIndex_1":0,"rangeLow":Float(-12),"rangeHigh":Float(0),"kSavedValueDoubleKey":Double(-6),"inputControlEvent":["type":5,"controllerID":71,"channelID":2]]
        let macroArchive=try NSKeyedArchiver.archivedData(withRootObject:["7":[row]],requiringSecureCoding:false)
        for i in 0..<4{source.append(UInt8((macroArchive.count >> (i*8)) & 255))};source.append(macroArchive)
        var draft=try MainStageProcessing.translate(source)
        draft.hasMIDITransform=true
        assert(draft.effects.map(\.kind)==[9,7,6,5,17,5])
        assert(draft.effectNotes.count==draft.effects.count)
        assert(draft.slotIndices==[0,3,4,5] && draft.instrumentIndices==[1,2])
        assert(draft.effectNotes[1].contains{$0.contains("Channel EQ")} && draft.effectNotes[2].contains{$0.contains("Compressor")})

        var layer=Layer(name:"Source channel",instrument:-1,gain:0.2)
        layer.effects[2]=AudioEffect.factoryDefault(kind:13)
        var legacy=AudioEffect.factoryDefault(kind:5)
        legacy.parameters=AudioEffectCatalog.defaults(for:5)
        var legacyRack=ImportedRack();legacyRack.mainStageUnityControllers=false;legacyRack.effects=[legacy];legacyRack.macros=[ImportedMacro(index:0,name:"Legacy macro",value:0,bindings:[ImportedMacroBinding(effect:0,parameter:0,minimum:0,maximum:1)])]
        layer.importedRack=legacyRack
        var selection=MainStageProcessing.Selection()
        selection.audio=[5,3,4]
        selection.midi=MIDIProgram(kind:.arpeggiator);selection.midiEnabled=false
        let applied=try draft.applying(to:layer,selection:selection)
        let selected=applied.layer
        assert(selected.effects.map(\.kind)==[5,17,5])
        assert(selected.effects[1].enabled==false,"Source bypass must survive selection")
        assert(selected.channelSettings.equalizer[0].frequency==79 && selected.channelSettings.equalizer[1].frequency==198)
        assert(selected.channelSettings.equalizer[1].gain == -2 && selected.channelSettings.equalizer[1].q==0.707)
        assert(selected.channelSettings.eqEnabled)
        assert(selected.channelSettings.compressorEnabled)
        assert(abs(selected.channelSettings.compressorAttack-0.01)<0.000001 && abs(selected.channelSettings.compressorRelease-0.37)<0.000001)
        assert(selected.channelSettings.ratio==12 && selected.channelSettings.threshold == -38)
        assert(abs((selected.channelSettings.compressorMix ?? 0)-0.75)<0.000001 && selected.channelSettings.makeup==8.5)
        assert(selected.channelSettings.compressorInputGain==0)
        assert(selected.importedRack?.effects==[legacy] && selected.importedRack?.macros.count==1 && selected.importedRack?.mainStageUnityControllers==true,"Legacy rack processing and macros must be preserved")
        assert(selected.midiProgram?.kind == .arpeggiator && selected.midiEffectEnabled==false)
        assert(selected.mainStageSource?.effects.count==6 && selected.mainStageSource?.selectedAudio==[3,4,5])
        assert(selected.mainStageSource?.hasMIDITransform==true && selected.mainStageSource?.selectedMIDI?.kind == .arpeggiator)
        assert(selected.mainStageSource?.omitted.count==1 && selected.mainStageSource!.omitted[0].contains("Gain"))
        assert(applied.notes.contains{$0.contains("source MIDI transform")})
        assert(applied.notes.contains{$0.contains("Smart Control")})
        assert(selected.mainStageSource?.valid==true)
        let restored=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(selected))
        assert(restored==selected,"Selected values, bypass, MIDI and source record must survive persistence")
        var setlist=Setlist();setlist.patches=[Patch(name:"Selected",layers:[restored],snapshots:[])]
        try setlist.validate()

        var tooMany=selection;tooMany.audio=[0,3,4,5]
        do {_ = try draft.applying(to:layer,selection:tooMany);assertionFailure("A fourth audio effect was accepted")}catch{}
        var duplicate=selection;duplicate.audio=[3,3]
        do {_ = try draft.applying(to:layer,selection:duplicate);assertionFailure("A duplicate slot selection was accepted")}catch{}
        var instrument=selection;instrument.audio=[1]
        do {_ = try draft.applying(to:layer,selection:instrument);assertionFailure("EQ was assigned to an audio slot")}catch{}

        let empty=try draft.applying(to:layer,selection:MainStageProcessing.Selection())
        assert(empty.layer.effects[0].kind==0 && empty.layer.effects[1].kind==0 && empty.layer.effects[2].kind==13,"Empty selection must not fill or erase existing slots")
        assert(empty.layer.mainStageSource?.selectedAudio.isEmpty==true && empty.layer.mainStageSource?.omitted.count==4)
        assert(empty.layer.channelSettings.equalizer[0].frequency==79,"EQ maps even when no audio slot is selected")

        var legacyLayer=Layer(name:"Legacy",instrument:-1,gain:0.5)
        let legacyData=try JSONEncoder().encode(legacyLayer)
        legacyLayer=try JSONDecoder().decode(Layer.self,from:legacyData)
        assert(legacyLayer.mainStageSource==nil,"Legacy layers must decode without a source record")
        assert(legacyLayer.effects.count==3 && legacyLayer.importedRack==nil)

        var sourceSelection=MainStageProcessing.Selection();sourceSelection.audio=[3,4]
        let twoSlots=try draft.applying(to:layer,selection:sourceSelection)
        assert(twoSlots.layer.effects.map(\.kind)==[5,17,13],"Unselected fourth slot keeps the destination effect")
        print("PASS: source effects select in source order, EQ/compressor map to instrument controls, overflow/traversal selections fail, source macros/MIDI/bypass persist and legacy racks/layers remain compatible")
    }
}
