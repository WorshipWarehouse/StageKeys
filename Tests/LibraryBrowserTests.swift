import Foundation
@main struct LibraryBrowserTests {
    static func main() throws {
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
