import Foundation
import CoreMIDI
@main struct MIDIInputTests {
 static func main() throws {
    let input = MIDIInput()
    var events: [(Int32,UInt8,UInt8,UInt8)] = [], removed: [Int32] = [], changes = 0
    input.onSourceEvent = { events.append(($0,$1,$2,$3)) }
    input.onDisconnect = { removed.append($0) }
    input.onDevices = { _,error in assert(error == nil,error ?? ""); changes += 1 }
    input.start(); input.start() // idempotent
    var client = MIDIClientRef(), a = MIDIEndpointRef(), b = MIDIEndpointRef()
    assert(MIDIClientCreateWithBlock("StageKeys Keyboard Test" as CFString,&client,nil)==noErr)
    defer { if a != 0 { MIDIEndpointDispose(a) }; if b != 0 { MIDIEndpointDispose(b) }; input.stop(); MIDIClientDispose(client) }
    let token=UUID().uuidString
    assert(MIDISourceCreate(client,"Keyboard A \(token)" as CFString,&a)==noErr)
    assert(MIDISourceCreate(client,"Keyboard B \(token)" as CFString,&b)==noErr)
    func wait(_ condition: ()->Bool) { let end=Date().addingTimeInterval(3); while !condition() && Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }; assert(condition()) }
    wait { input.sources.contains(where:{$0.endpoint==a && $0.connected}) && input.sources.contains(where:{$0.endpoint==b && $0.connected}) }
    assert(!input.sources.contains(where:{$0.name == "StageKeys to External App"}))
    let idA=input.sources.first(where:{$0.endpoint==a})!.id, idB=input.sources.first(where:{$0.endpoint==b})!.id
    let before=changes
    for _ in 0..<20 { input.refresh() }
    assert(changes==before && removed.isEmpty,"Refresh must preserve stable connections")
    func send(_ source:MIDIEndpointRef,_ status:UInt8,_ note:UInt8,_ velocity:UInt8) {
        var list=MIDIPacketList()
        withUnsafeMutablePointer(to:&list) { p in
            let packet=MIDIPacketListInit(p); let bytes:[UInt8]=[status,note,velocity]
            bytes.withUnsafeBufferPointer { v in assert(MIDIPacketListAdd(p,MemoryLayout<MIDIPacketList>.size,packet,0,3,v.baseAddress!) != nil) }
            assert(MIDIReceived(source,p)==noErr)
        }
    }
    send(a,0x90,60,100); send(b,0x92,60,80)
    wait { events.count==2 }
    assert(events[0].0==idA && events[0].1==0x90 && events[0].2==60 && events[0].3==100)
    assert(events[1].0==idB && events[1].1==0x92)
    send(a,0xb0,64,127); send(a,0x80,60,0); send(b,0x82,60,0)
    wait { events.count==5 }
    MIDIEndpointDispose(a); a=0
    wait { removed.contains(idA) }
    assert(!removed.contains(idB))
    assert(input.sources.contains(where:{$0.id==idB && $0.connected}))
    send(b,0x92,67,127); wait { events.count==6 }
    print("PASS: MIDI plug-and-play after launch, two sources/channels, stable refresh, sustain, note-off, unplug and surviving input")
 }
}
