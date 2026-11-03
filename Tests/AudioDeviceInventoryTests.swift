import Foundation
import AudioToolbox

@main struct AudioDeviceInventoryTests {
    static func main() throws {
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
        print("PASS device inventory: mono/stereo/multi-stream, truncated headers/entries, invalid counts/pointers, overflow, byte budgets and unique device IDs")
    }
}
