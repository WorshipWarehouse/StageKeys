import Foundation
import CoreMIDI
@main struct ExternalMIDITests {
    static func main() throws {
        let output = try ExternalMIDIOutput()
        var source: MIDIEndpointRef = 0
        for i in 0..<MIDIGetNumberOfSources() {
            let candidate = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(candidate, kMIDIPropertyName, &name)
            if name?.takeRetainedValue() as String? == "StageKeys to External App" { source = candidate }
        }
        assert(source != 0)
        var client = MIDIClientRef(), port = MIDIPortRef()
        let lock = NSLock()
        var events: [[UInt8]] = []
        assert(MIDIClientCreateWithBlock("StageKeys Test Listener" as CFString, &client, nil) == noErr)
        assert(MIDIInputPortCreateWithBlock(client, "Listener" as CFString, &port) { list, _ in
            let packet = list.pointee.packet
            var bytes = packet.data
            let captured = withUnsafeBytes(of: &bytes) { Array($0.prefix(Int(packet.length))) }
            lock.lock(); events.append(captured); lock.unlock()
        } == noErr)
        defer { MIDIPortDispose(port); MIDIClientDispose(client) }
        assert(MIDIPortConnectSource(port, source, nil) == noErr)
        try output.send(destinationID: ExternalMIDIOutput.broadcastID, status: 0x92, data1: 60, data2: 100)
        try output.send(destinationID: ExternalMIDIOutput.broadcastID, status: 0x82, data1: 60, data2: 0)
        let end = Date().addingTimeInterval(2)
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            lock.lock(); let count = events.count; lock.unlock()
            if count >= 2 { break }
        }
        lock.lock(); let result = events; lock.unlock()
        assert(result == [[0x92,60,100],[0x82,60,0]], "Virtual MIDI delivery failed: \(result)")
        print("PASS: external-app virtual source delivers channel-specific note-on and note-off")
    }
}
