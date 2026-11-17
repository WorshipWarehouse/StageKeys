import Foundation
import AudioToolbox

@main struct AudioDeviceInventoryTests {
    static func main() throws {
        let other=AudioOutputDevice(id:2,name:"Other Device",channels:8)
        assert(AudioOutputDevice.selectedChannels(in:[other],id:1,name:"Old Device")==nil,"A stale selected ID must not adopt another device's pairs")
        assert(AudioOutputDevice.selectedChannels(in:[other],id:2,name:"Other Device")==8)
        assert(AudioOutputDevice.selectedChannels(in:[other],id:nil,name:"Old Device")==nil,"A stale named route cannot borrow another port’s channels")
        let unknown=AudioOutputDevice(id:0,name:"iOS route",channels:0,channelCountKnown:false)
        assert(AudioOutputDevice.selectedChannels(in:[unknown],id:nil,name:"iOS route")==nil,"A missing channel list is unknown, not stereo")

        func word(_ value: UInt32) -> Data { var value = value; return withUnsafeBytes(of: &value) { Data($0) } }
        let offset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!
        func list(_ channels: [UInt32]) -> Data {
            var data = Data(count: offset + channels.count * MemoryLayout<AudioBuffer>.stride)
            data.replaceSubrange(0..<4, with: word(UInt32(channels.count)))
            for (index, count) in channels.enumerated() {
                let start = offset + index * MemoryLayout<AudioBuffer>.stride
                data.replaceSubrange(start..<start+4, with: word(count))
                // Deliberately invalid mData pointer bytes must never be followed.
                let pointer = start + MemoryLayout<AudioBuffer>.offset(of: \.mData)!
                data.replaceSubrange(pointer..<pointer+MemoryLayout<UnsafeMutableRawPointer?>.size, with: repeatElement(UInt8(255), count: MemoryLayout<UnsafeMutableRawPointer?>.size))
            }
            return data
        }
        func rejected(_ action: () throws -> Void) {
            do { try action(); assertionFailure("Malformed inventory accepted") }
            catch AudioDeviceError.invalidInventory {}
            catch { assertionFailure("Unexpected error: \(error)") }
        }
        let emptyChannels = try AudioDeviceInventoryData.outputChannels(word(0))
        assert(emptyChannels == 0)
        for channels: [UInt32] in [[1], [2], [1,1], [2,2,2,2], [0,2]] {
            let total = try AudioDeviceInventoryData.outputChannels(list(channels))
            assert(total == channels.reduce(0,+))
        }
        rejected { _ = try AudioDeviceInventoryData.outputChannels(Data()) }
        rejected { _ = try AudioDeviceInventoryData.outputChannels(Data(repeating: 0, count: 3)) }
        var truncated = list([2,2]); truncated.removeLast()
        rejected { _ = try AudioDeviceInventoryData.outputChannels(truncated) }
        var excessive = list([2]); excessive.replaceSubrange(0..<4, with: word(UInt32.max))
        rejected { _ = try AudioDeviceInventoryData.outputChannels(excessive) }
        rejected { _ = try AudioDeviceInventoryData.outputChannels(list([UInt32.max,1])) }
        rejected { _ = try AudioDeviceInventoryData.outputChannels(Data(repeating: 0, count: Int(AudioDeviceInventoryData.maximumBytes)+1)) }
        let emptyIDs = try AudioDeviceInventoryData.deviceIDs(Data())
        assert(emptyIDs.isEmpty)
        let ids = try AudioDeviceInventoryData.deviceIDs(word(7)+word(0)+word(9)+word(7))
        assert(ids == [7,9])
        rejected { _ = try AudioDeviceInventoryData.deviceIDs(word(7)+Data([0])) }
        rejected { _ = try AudioDeviceInventoryData.deviceIDs(Data(repeating: 0, count: Int(AudioDeviceInventoryData.maximumBytes)+1)) }
        // Exercise all truncation boundaries of a multi-stream response.
        let complete = list([1,2,1,2])
        for length in 0..<complete.count {
            rejected { _ = try AudioDeviceInventoryData.outputChannels(Data(complete.prefix(length))) }
        }
        // Output-pair enumeration (#107 stage 1): pairs come from the device's
        // real channel count, a leftover odd channel is not a stereo pair, and a
        // stale index is named instead of being substituted.
        assert(FlexRouting.pairs(channels: 0).isEmpty && FlexRouting.pairs(channels: 1).isEmpty)
        assert(FlexRouting.pairs(channels: 2) == [FlexOutputPair(index: 0)])
        assert(FlexRouting.pairs(channels: 2)[0].title == "Output 1–2")
        assert(FlexRouting.pairs(channels: 4).map(\.index) == [0, 1])
        assert(FlexRouting.pairs(channels: 4)[1].title == "Output 3–4")
        assert(FlexRouting.pairs(channels: 7).map(\.index) == [0, 1, 2])
        assert(FlexRouting.unpairedChannels(7) == 1 && FlexRouting.unpairedChannels(8) == 0)
        assert(FlexRouting.pairs(channels: 4_096).count == FlexOutputPair.maximumPairs)
        assert(FlexRouting.pairs(channels: .max).count == FlexOutputPair.maximumPairs)
        assert(FlexRouting.state(pair: 0, channels: 2) == .available(FlexOutputPair(index: 0)))
        assert(FlexRouting.state(pair: 1, channels: 2) == .pairUnavailable(1))
        assert(FlexRouting.state(pair: -1, channels: 4) == .pairUnavailable(0))
        assert(FlexRouting.state(pair: 0, channels: 1) == .monoDevice)
        assert(FlexRouting.state(pair: 0, channels: 0) == .noOutputs)
        assert(FlexRouting.state(pair: 0, channels: nil) == .deviceUnavailable)
        assert(FlexRouting.state(pair: 0, channels: 2).isAvailable && !FlexRouting.state(pair: 1, channels: 2).isAvailable)
        assert(FlexRouting.state(pair: 1, channels: 2).message.contains("Output 3–4"), "A stale pair must be named, not substituted")
        assert(FlexRouting.summary(channels: 6).contains("3 stereo pairs") && FlexRouting.summary(channels: 3).contains("unpaired channel"))
        assert(FlexRouting.summary(channels: 0).contains("No output channels") && FlexRouting.summary(channels: 1).contains("no stereo pair"))
        print("PASS device inventory: mono/stereo/multi-stream, truncated headers/entries, invalid counts/pointers, overflow, byte budgets, unique device IDs and reported stereo output pairs")
    }
}
