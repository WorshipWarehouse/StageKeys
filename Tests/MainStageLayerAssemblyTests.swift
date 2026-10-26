import Foundation

@main struct MainStageLayerAssemblyTests {
    static func main() throws {
        let archive=UUID().uuidString
        let channels=(0..<2).map{index in MainStagePatch.Channel(name:"Channel \(index)",file:"\(index).cst",sha256:String(repeating:String(index),count:64),instruments:["\(index).exs"],devices:[],hasMappings:true,hasMIDIState:true)}
        let report=MainStagePatch.Report(sourceArchiveID:archive,name:"Source Patch",channels:channels,blockers:["Bus routing requires review"],preservedFiles:[:])
        let entries=channels.enumerated().map{index,channel -> LibrarySound in
            var layer=Layer(name:"Original",instrument:-1,gain:0.23+Float(index)*0.1)
            layer.external=ExternalSound(kind:.samplerPreset,name:"Fixture",fileName:"fixture.aupreset")
            layer.pan = -0.3;layer.channelSettings.equalizer[3].gain = -4
            layer.effects[0]=AudioEffect.factoryDefault(kind:13);layer.effects[0].enabled=false
            layer.importedRack=ImportedRack(effects:[AudioEffect.factoryDefault(kind:3)])
            layer.midiProgram=MIDIProgram(kind:.octaveUp)
            return LibrarySound(id:"mainstage-channel-"+channel.sha256+"-fixture",name:channel.name,collection:"My Sounds",sound:layer.external,layer:layer,sourceArchiveID:archive,conversionNotes:["Approximate source processor"])
        }
        let patch=try MainStagePatch.assembledChannels(report,entries:Array(entries.reversed()))
        assert(patch.layers.count==15 && patch.layers.prefix(2).map(\.name)==channels.map(\.name))
        for i in 0..<2 {
            let a=patch.layers[i],b=entries[i].layer!
            assert(a.id != b.id && a.gain==b.gain && a.pan==b.pan && a.effects==b.effects)
            assert(a.channelSettings==b.channelSettings && a.importedRack==b.importedRack && a.midiProgram==b.midiProgram)
        }
        assert(patch.layers.dropFirst(2).allSatisfy{!$0.loaded})
        let restored=try JSONDecoder().decode(Patch.self,from:JSONEncoder().encode(patch))
        assert(restored.conversionNotes==patch.conversionNotes && restored.conversionNotes!.contains("Bus routing requires review"))
        for invalid in [Array(entries.prefix(1)),entries+[entries[0]]] {
            do {_ = try MainStagePatch.assembledChannels(report,entries:invalid);assertionFailure("Incomplete/ambiguous patch assembled")}catch{}
        }
        // A channel can also be converted by hosting the Audio Unit it saved.
        let hostedChannel=MainStagePatch.Channel(name:"Pad",file:"pad.cst",sha256:String(repeating:"a",count:64),instruments:[],devices:[.init(name:"OB-Xd",offset:0,byteCount:1,format:"PSDD")],hasMappings:false,hasMIDIState:false)
        assert(hostedChannel.isConvertible,"A saved Audio Unit makes a channel convertible")
        let hostedReport=MainStagePatch.Report(sourceArchiveID:archive,name:"Hosted Patch",channels:[hostedChannel],blockers:[],preservedFiles:[:])
        var hostedLayer=Layer(name:"Pad",instrument:-1,gain:1)
        hostedLayer.external=ExternalSound(kind:.audioUnit,name:"OB-Xd",component:ExternalAUIdentity(type:0x61756d75,subtype:0x4f627864,manufacturer:0x44445350,name:"OB-Xd"))
        hostedLayer.pluginState=Data(repeating:7,count:32)
        let hostedEntry=LibrarySound(id:"mainstage-channel-"+hostedChannel.sha256+"-fixture",name:"Pad",collection:"MainStage Patches",sound:hostedLayer.external,layer:hostedLayer,sourceArchiveID:archive,conversionNotes:["hosted OB-Xd"])
        let hostedPatch=try MainStagePatch.assembledChannels(hostedReport,entries:[hostedEntry])
        assert(hostedPatch.layers.first?.external?.kind == .audioUnit && hostedPatch.layers.first?.pluginState==hostedLayer.pluginState,"A hosted Audio Unit must assemble with its saved state")
        do {_ = try MainStagePatch.assembledChannels(hostedReport,entries:[]);assertionFailure("An unconverted Audio Unit channel assembled")}catch{}
        print("PASS: layered conversion preserves source order, effects, bypass, macros/MIDI, gain/EQ and persistent warnings; missing/ambiguous channels rejected")
    }
}
