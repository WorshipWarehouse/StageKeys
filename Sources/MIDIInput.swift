import Foundation
import CoreMIDI

struct MIDIInputSource: Identifiable, Equatable {
    var id: Int32
    var endpoint: MIDIEndpointRef
    var name: String
    var connected: Bool
}
struct MIDIKnownDevice: Identifiable, Equatable {
    var id: Int32
    var name: String
    var online: Bool
}
private final class MIDIReadContext {
    weak var input: MIDIInput?
    let endpoint: MIDIEndpointRef
    init(_ input: MIDIInput, _ endpoint: MIDIEndpointRef) { self.input = input; self.endpoint = endpoint }
}
private let receiveInput: @convention(c) (UnsafeMutableRawPointer?, UInt8, UInt8, UInt8) -> Void = { context, status, a, b in
    guard let context else { return }
    let receiver = Unmanaged<MIDIReadContext>.fromOpaque(context).takeUnretainedValue()
    let endpoint = receiver.endpoint
    DispatchQueue.main.async { [weak input = receiver.input] in input?.deliver(endpoint: endpoint, status: status, a: a, b: b) }
}
/// CoreMIDI owns the receive thread. Device state and every public callback belong
/// to main. Connections are diffed, so an unrelated notification cannot drop notes.
final class MIDIInput {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: [MIDIEndpointRef: Int32] = [:]
    private var poll: Timer?
    private var refreshWork: DispatchWorkItem?
    private var lastError: String?
    private(set) var sources: [MIDIInputSource] = []
    private(set) var devices: [MIDIKnownDevice] = []
    var onEvent: ((UInt8, UInt8, UInt8) -> Void)?
    var onSourceEvent: ((Int32, UInt8, UInt8, UInt8) -> Void)?
    var onDevices: ((Int, String?) -> Void)?
    var onInventory: (([MIDIInputSource], [MIDIKnownDevice]) -> Void)?
    var onDisconnect: ((Int32) -> Void)?
    private static func string(_ object: MIDIObjectRef, _ property: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }
    private static func integer(_ object: MIDIObjectRef, _ property: CFString) -> Int32 {
        var value: Int32 = 0; MIDIObjectGetIntegerProperty(object, property, &value); return value
    }
    func start() {
        precondition(Thread.isMainThread)
        guard client == 0 else { refresh(); return }
        var result = MIDIClientCreateWithBlock("StageKeys Input" as CFString, &client) { [weak self] notification in
            switch notification.pointee.messageID {
            case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged, .msgPropertyChanged, .msgIOError:
                DispatchQueue.main.async { self?.scheduleRefresh() }
            default: break
            }
        }
        guard result == noErr else { report("Could not start MIDI (\(result))."); return }
        result = MIDIInputPortCreateWithProtocol(client, "StageKeys Keyboard Input" as CFString, ._1_0, &port) { [weak self] list, refCon in
            guard let self, let refCon else { return }
            let endpoint = MIDIEndpointRef(UInt(bitPattern: refCon))
            let receiver = MIDIReadContext(self, endpoint)
            sk_read_midi(list, receiveInput, Unmanaged.passUnretained(receiver).toOpaque())
        }
        guard result == noErr else {
            MIDIClientDispose(client); client = 0
            report("Could not open MIDI input (\(result))."); return
        }
        refresh()
        // Some USB drivers miss a setup notification after sleep/reconnection.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common); poll = timer
    }
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.1, execute: work)
    }
    private func report(_ error: String?) {
        if error != lastError { lastError = error; onDevices?(connected.count, error) }
    }
    func refresh() {
        precondition(Thread.isMainThread)
        guard port != 0 else { return }
        var discovered: [MIDIInputSource] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            guard endpoint != 0, Self.integer(endpoint,kMIDIPropertyOffline) == 0 else { continue }
            let name = Self.string(endpoint,kMIDIPropertyName)
            guard name != "StageKeys to External App" else { continue }
            let display = Self.string(endpoint,kMIDIPropertyDisplayName)
            let identity = Self.integer(endpoint,kMIDIPropertyUniqueID)
            discovered.append(MIDIInputSource(id: identity == 0 ? Int32(bitPattern:endpoint) : identity, endpoint: endpoint, name: display.isEmpty ? (name.isEmpty ? "MIDI Keyboard" : name) : display, connected: false))
        }
        let endpoints = Set(discovered.map(\.endpoint))
        for endpoint in Array(connected.keys) where !endpoints.contains(endpoint) {
            MIDIPortDisconnectSource(port, endpoint)
            if let identity = connected.removeValue(forKey: endpoint) { onDisconnect?(identity) }
        }
        var failure: String?
        for i in discovered.indices {
            let source = discovered[i]
            if connected[source.endpoint] == nil {
                let result = MIDIPortConnectSource(port,source.endpoint,UnsafeMutableRawPointer(bitPattern:UInt(source.endpoint)))
                if result == noErr { connected[source.endpoint] = source.id }
                else { failure = "Could not connect \(source.name) (\(result))." }
            }
            discovered[i].connected = connected[source.endpoint] != nil
        }
        var known: [MIDIKnownDevice] = []
        for i in 0..<MIDIGetNumberOfDevices() {
            let device = MIDIGetDevice(i)
            guard MIDIDeviceGetNumberOfEntities(device) > 0 else { continue }
            let display = Self.string(device,kMIDIPropertyDisplayName)
            let model = Self.string(device,kMIDIPropertyModel)
            let name = display.isEmpty ? (model.isEmpty ? Self.string(device,kMIDIPropertyName) : model) : display
            guard !name.isEmpty else { continue }
            known.append(MIDIKnownDevice(id:Self.integer(device,kMIDIPropertyUniqueID), name:name, online:Self.integer(device,kMIDIPropertyOffline)==0))
        }
        discovered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let changed = discovered != sources || known != devices
        sources = discovered; devices = known
        if changed { onInventory?(sources, devices); onDevices?(connected.count,failure); lastError = failure }
        else { report(failure) }
    }
    fileprivate func deliver(endpoint: MIDIEndpointRef, status: UInt8, a: UInt8, b: UInt8) {
        guard let identity = connected[endpoint] else { return }
        onSourceEvent?(identity,status,a,b); onEvent?(status,a,b)
    }
    func stop() {
        precondition(Thread.isMainThread)
        refreshWork?.cancel(); poll?.invalidate(); poll=nil
        for (endpoint,id) in connected { MIDIPortDisconnectSource(port,endpoint); onDisconnect?(id) }
        connected.removeAll(); sources=[]
        if port != 0 { MIDIPortDispose(port); port=0 }
        if client != 0 { MIDIClientDispose(client); client=0 }
    }
    deinit { refreshWork?.cancel(); poll?.invalidate(); if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
}
