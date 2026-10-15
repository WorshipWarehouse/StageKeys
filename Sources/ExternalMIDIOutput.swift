import Foundation
import CoreMIDI

struct ExternalMIDIDestination: Identifiable, Hashable {
    var id: Int32
    var name: String
    var endpoint: MIDIEndpointRef
}

/// Sends MIDI to hardware or virtual app destinations. Audio return requires the
/// destination's own audio routing or an Audio Unit; MIDI is not an audio cable.
final class ExternalMIDIOutput {
    static let broadcastID: Int32 = -2147483647
    private var source = MIDIEndpointRef()
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    init() throws {
        var result = MIDIClientCreateWithBlock("StageKeys Output" as CFString, &client, nil)
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        result = MIDIOutputPortCreate(client, "StageKeys Output" as CFString, &port)
        guard result == noErr else {
            MIDIClientDispose(client); client = 0
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        result = MIDISourceCreate(client, "StageKeys to External App" as CFString, &source)
        guard result == noErr else { MIDIPortDispose(port); MIDIClientDispose(client); port = 0; client = 0; throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }
    static func destinations() -> [ExternalMIDIDestination] {
        [ExternalMIDIDestination(id: broadcastID, name: "StageKeys to External App", endpoint: 0)] + (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { return nil }
            var identity = Int32()
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &identity)
            var value: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value)
            return ExternalMIDIDestination(id: identity, name: value?.takeRetainedValue() as String? ?? "MIDI Output", endpoint: endpoint)
        }
    }
    /// Resolve the persistent unique ID afresh so disconnected endpoints are not used.
    func send(destinationID: Int32, status: UInt8, data1: UInt8, data2: UInt8) throws {
        guard let destination = Self.destinations().first(where: { $0.id == destinationID }) else {
            throw NSError(domain: "StageKeysMIDI", code: 1, userInfo: [NSLocalizedDescriptionKey: "The MIDI output is disconnected."])
        }
        var list = MIDIPacketList()
        let result: OSStatus = withUnsafeMutablePointer(to: &list) { pointer in
            let packet = MIDIPacketListInit(pointer)
            let bytes: [UInt8] = [status, min(127, data1), min(127, data2)]
            return bytes.withUnsafeBufferPointer { buffer in
                MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, 3, buffer.baseAddress!)
                return destinationID == Self.broadcastID ? MIDIReceived(source, pointer) : MIDISend(port, destination.endpoint, pointer)
            }
        }
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }
    deinit {
        if source != 0 { MIDIEndpointDispose(source) }
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }
}
