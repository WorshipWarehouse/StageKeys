import Foundation
import CoreMIDI

struct ExternalMIDIDestination: Identifiable, Hashable {
    var id: Int32
    var name: String
    var endpoint: MIDIEndpointRef
    /// Core MIDI reports offline endpoints for a while after a device is unplugged.
    var online = true
    /// StageKeys' own virtual port, or an endpoint that resolves to it.
    var virtual = false
}

/// Pure routing rules, kept separate from Core MIDI so they can be verified
/// without external apps or hardware.
enum ExternalMIDIRouting {
    /// Hosted ports first, then online devices, then offline devices; name order
    /// inside each group so the picker stays stable as devices come and go.
    static func sorted(_ destinations: [ExternalMIDIDestination]) -> [ExternalMIDIDestination] {
        destinations.sorted { lhs, rhs in
            if lhs.virtual != rhs.virtual { return lhs.virtual }
            if lhs.online != rhs.online { return lhs.online }
            let compared = lhs.name.localizedStandardCompare(rhs.name)
            return compared == .orderedSame ? lhs.id < rhs.id : compared == .orderedAscending
        }
    }
    /// Sending to our own virtual source would feed output straight back into the
    /// input port. The broadcast entry is the supported way to reach that source.
    static func isLoop(_ destination: ExternalMIDIDestination, ownSourceID: Int32) -> Bool {
        destination.id != ExternalMIDIOutput.broadcastID && ownSourceID != 0 && destination.id == ownSourceID
    }
    /// Resolve a persisted unique ID, skipping offline endpoints and loops.
    static func resolve(_ id: Int32, in destinations: [ExternalMIDIDestination], ownSourceID: Int32) -> ExternalMIDIDestination? {
        destinations.first { $0.id == id && $0.online && !isLoop($0, ownSourceID: ownSourceID) }
    }
}

/// Sends MIDI to hardware or virtual app destinations. Audio return requires the
/// destination's own audio routing or an Audio Unit; MIDI is not an audio cable.
final class ExternalMIDIOutput {
    static let broadcastID: Int32 = -2147483647
    private var source = MIDIEndpointRef()
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var cache: [ExternalMIDIDestination]?
    /// Called on the main queue after Core MIDI reports a setup change.
    var onChange: (() -> Void)?
    private(set) var ownSourceID: Int32 = 0
    init() throws {
        // Setup changes invalidate the cached destination list, so a reconnected
        // interface is usable without reopening the app or the picker.
        var result = MIDIClientCreateWithBlock("StageKeys Output" as CFString, &client) { [weak self] notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                DispatchQueue.main.async { self?.invalidate() }
            default: break
            }
        }
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        result = MIDIOutputPortCreate(client, "StageKeys Output" as CFString, &port)
        guard result == noErr else {
            MIDIClientDispose(client); client = 0
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        result = MIDISourceCreate(client, "StageKeys to External App" as CFString, &source)
        guard result == noErr else { MIDIPortDispose(port); MIDIClientDispose(client); port = 0; client = 0; throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        var identity = Int32()
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &identity)
        ownSourceID = identity
    }
    private func invalidate() {
        cache = nil
        onChange?()
    }
    /// Enumerate the current destinations. Runs on setup changes, an explicit
    /// refresh, or after a send resolves nothing, never per output event.
    @discardableResult func refresh() -> [ExternalMIDIDestination] {
        let destinations = ExternalMIDIRouting.sorted(Self.enumerate(ownSourceID: ownSourceID))
        cache = destinations
        return destinations
    }
    var destinations: [ExternalMIDIDestination] {
        if let cache { return cache }
        return refresh()
    }
    static func enumerate(ownSourceID: Int32) -> [ExternalMIDIDestination] {
        var list = [ExternalMIDIDestination(id: broadcastID, name: "StageKeys to External App", endpoint: 0, online: true, virtual: true)]
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            var identity = Int32()
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &identity)
            var offline = Int32()
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
            var value: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value)
            list.append(ExternalMIDIDestination(id: identity, name: value?.takeRetainedValue() as String? ?? "MIDI Output",
                                                endpoint: endpoint, online: offline == 0, virtual: identity == ownSourceID))
        }
        return list
    }
    /// Resolve the persistent unique ID afresh so disconnected endpoints are not
    /// used, and report a clear error instead of dropping the event silently.
    func send(destinationID: Int32, status: UInt8, data1: UInt8, data2: UInt8) throws {
        var destination = ExternalMIDIRouting.resolve(destinationID, in: cache ?? [], ownSourceID: ownSourceID)
        if destination == nil {
            destination = ExternalMIDIRouting.resolve(destinationID, in: refresh(), ownSourceID: ownSourceID)
        }
        guard let destination else {
            throw NSError(domain: "StageKeysMIDI", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "MIDI output \\(destinationID) is disconnected. Reconnect it or choose another destination."])
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
