import CoreMIDI
import Foundation

enum ProbeError: Error { case client(OSStatus), source(OSStatus), packet(OSStatus), sourceNotFound(String) }

@main
struct SendMIDIProbe {
    static func main() throws {
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--list" {
            for index in 0..<MIDIGetNumberOfSources() {
                let candidate = MIDIGetSource(index)
                var value: Unmanaged<CFString>?
                if MIDIObjectGetStringProperty(candidate, kMIDIPropertyDisplayName, &value) == noErr,
                   let name = value?.takeRetainedValue() { print(name) }
            }
            return
        }
        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        var ownsSource = false
        var status = MIDIClientCreateWithBlock("StageKeys Effect Probe" as CFString, &client) { _ in }
        guard status == noErr else { throw ProbeError.client(status) }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--existing" {
            let wanted = CommandLine.arguments[2].lowercased()
            for index in 0..<MIDIGetNumberOfSources() {
                let candidate = MIDIGetSource(index)
                var value: Unmanaged<CFString>?
                guard MIDIObjectGetStringProperty(candidate, kMIDIPropertyDisplayName, &value) == noErr,
                      let name = value?.takeRetainedValue() as String?, name.lowercased().contains(wanted) else { continue }
                source = candidate
                FileHandle.standardError.write(Data("Using MIDI source: \(name)\n".utf8))
                break
            }
            guard source != 0 else { throw ProbeError.sourceNotFound(CommandLine.arguments[2]) }
        } else {
            status = MIDISourceCreate(client, "StageKeys Effect Probe" as CFString, &source)
            guard status == noErr else { throw ProbeError.source(status) }
            ownsSource = true
        }
        defer { if ownsSource { MIDIEndpointDispose(source) }; MIDIClientDispose(client) }

        func send(_ command: UInt8, _ data1: UInt8, _ data2: UInt8) throws {
            var list = MIDIPacketList()
            let result = withUnsafeMutablePointer(to: &list) { pointer -> OSStatus in
                let packet = MIDIPacketListInit(pointer)
                let bytes = [command, data1, data2]
                _ = bytes.withUnsafeBufferPointer {
                    MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, $0.count, $0.baseAddress!)
                }
                return MIDIReceived(source, pointer)
            }
            guard result == noErr else { throw ProbeError.packet(result) }
        }

        // Allow hosts to observe and connect the newly-created virtual source.
        Thread.sleep(forTimeInterval: 1.0)
        try send(0xB0, 64, 0)
        try send(0xB0, 1, 0)
        for (note, velocity) in [(48, 32), (60, 64), (72, 96), (84, 127)] {
            try send(0x90, UInt8(note), UInt8(velocity))
            Thread.sleep(forTimeInterval: 0.45)
            try send(0x80, UInt8(note), 0)
            Thread.sleep(forTimeInterval: 0.35)
        }
        try send(0xB0, 64, 127)
        for note in [48, 55, 60, 64] { try send(0x90, UInt8(note), 83) }
        Thread.sleep(forTimeInterval: 1.5)
        for note in [48, 55, 60, 64] { try send(0x80, UInt8(note), 0) }
        try send(0xB0, 64, 0)
        Thread.sleep(forTimeInterval: 2.0)
        try send(0xB0, 123, 0)
    }
}
