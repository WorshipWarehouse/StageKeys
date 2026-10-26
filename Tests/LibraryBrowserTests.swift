import Foundation
@main struct LibraryBrowserTests {
    static func main() throws {
        assert(SoundTags.inferred(name:"Sharp Piano").category=="Acoustic Piano & Keys")
        assert(SoundTags.inferred(name:"Sharp Pad").category=="Pads")
        assert(SoundTags.inferred(name:"WarmPad").category=="Pads")
        assert(SoundTags.inferred(name:"Slow Arpeggio").category=="Arps & Sequences")
        assert(SoundTags.inferred(name:"Organism").category=="Other")
        assert(!SoundTags.inferred(name:"Monolith Pad").articulations.contains("Monophonic"))
        let unknown=BrowserSound.library(LibrarySound(id:"unknown",name:"Unknown Texture",collection:"My Sounds",hostPath:"/fixture.patch"))
        assert(unknown.values(.noteRange)==["Not Tagged"] && unknown.values(.timbre)==["Not Tagged"] && unknown.values(.articulation)==["Not Tagged"])
        var missing=LibraryQuery();missing.filters[.timbre]="Not Tagged";assert(missing.results([unknown]).count==1)
        let native=LibrarySound(id:"native-felt",name:"SK App Felt Piano v1_6",collection:"Sunday App · Native",sound:ExternalSound(kind:.samplerPreset,name:"Felt",fileName:"fixture.aupreset"))
        let voiced=SundayFactoryVoicing.feltRoom(from:native)!
        assert(voiced.sound==native.sound && voiced.layer!.channelSettings.validate())
        assert(voiced.layer!.channelSettings.compressorMix==0.68 && voiced.layer!.channelSettings.ratio==3)
        assert(voiced.layer!.channelSettings.equalizer[3].gain == -5.5 && voiced.layer!.effects[1].values[8]==0.23)
        assert(SoundTags.inferred(name:"Touchstone Piano - Sunday Sounds").type == "Acoustic Piano")
        assert(SoundTags.inferred(name:"Airy EP- Sunday Sounds").type == "Electric Piano")
        assert(SoundTags.inferred(name:"DX E Piano 1 | Ballad").type == "Electric Piano")

        let warm=BrowserSound.library(LibrarySound(id:"warm",name:"Warm Pad",collection:"Sunday Free Native · Volume 2",sound:ExternalSound(kind:.sample,name:"Warm Pad",fileName:"warm.wav")))
        let piano=BrowserSound.library(LibrarySound(id:"piano",name:"Felt Piano",collection:"My Sounds",sound:ExternalSound(kind:.sample,name:"Felt Piano",fileName:"felt.wav")))
        let host=BrowserSound.library(LibrarySound(id:"host",name:"Warm Pad",collection:"Sunday Free · Volume 2",hostPath:"/test.patch"))
        let sounds=[warm,piano,host]
        var query=LibraryQuery()
        assert(query.results(sounds).map(\.id) == ["piano","host","warm"])
        query.filters[.category]="Pads"
        assert(Set(query.results(sounds).map(\.id)) == ["warm","host"])
        query.filters[.availability]="Playable"
        assert(query.results(sounds).map(\.id) == ["warm"])
        assert(query.options(.category,in:sounds).contains("Acoustic Piano & Keys"))
        assert(!query.options(.library,in:sounds).contains("My Sounds"))
        query.search="warm volume 2"
        assert(query.results(sounds).map(\.id) == ["warm"])
        query.search="piano";assert(query.results(sounds).isEmpty)
        query=LibraryQuery();query.ascending=false
        assert(query.results(sounds).last?.id == "piano")
        query.filters[.timbre]="Warm";assert(query.results(sounds).count == 2)
        var recommended=warm;var recommendedTags=recommended.tags;recommendedTags.recommended=true
        recommended=BrowserSound(id:"recommended",name:"Z Pad",collection:warm.collection,tags:recommendedTags)
        query=LibraryQuery();query.order(by:.recommended)
        assert(query.results([piano,recommended,host]).map(\.id)==["recommended","piano","host"])
        query.ascending=false;assert(query.results([piano,recommended,host]).last?.id=="recommended")
        assert(SoundLibrary.cleanImportedName("Classic Pluck Synth- Sunday Sounds-1")=="Classic Pluck Synth")
        assert(SoundLibrary.cleanImportedName("Synth Brass Pad- Sundy Sounds")=="Synth Brass Pad")
        assert(SoundLibrary.cleanImportedName("Circular Echo- Layered Patch")=="Circular Echo")
        let old=Data("[{\"id\":\"old\",\"name\":\"Old\",\"collection\":\"My Sounds\",\"hostPath\":\"/old.patch\"}]".utf8)
        let decoded=try JSONDecoder().decode([LibrarySound].self,from:old);assert(decoded.first?.tags == nil)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let library=SoundLibrary(url:root.appendingPathComponent("library.json"))
        var tagged=warm.entry!;tagged.tags=warm.tags;tagged.sourceArchiveID="host"
        try library.write([tagged]);let read=try library.read();assert(read == [tagged])
        tagged.tags!.timbres=Array(repeating:"x",count:65)
        do{try library.write([tagged]);fatalError("Oversized metadata accepted")}catch{}
        print("PASS: library facets, combined search, sorting, availability, legacy decode and tagged persistence")
    }
}
