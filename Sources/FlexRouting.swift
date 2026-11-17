import Foundation

/// One stereo hardware output pair on the selected audio device.
///
/// StageKeys mixes every sound, the Tonic Pad and the click to pair 0 (Output
/// 1–2). The type exists so available pairs can be derived from the device's
/// real channel count and reported truthfully before per-sound routing (#107)
/// exists. A pair is never invented for a device that cannot carry it.
struct FlexOutputPair: Hashable, Identifiable {
    /// Reporting bound. A device advertising more pairs than this is truncated
    /// rather than trusted, so a malformed driver cannot grow the UI or report.
    static let maximumPairs = 16
    let index: Int
    var id: Int { index }
    var firstChannel: Int { index * 2 + 1 }
    var secondChannel: Int { index * 2 + 2 }
    var title: String { "Output \(firstChannel)–\(secondChannel)" }
}

/// Why a requested destination cannot be used on the selected device. A stale
/// pair is reported instead of being replaced, so a saved preference can never
/// silently route a sound to a different output.
enum FlexRouteState: Equatable {
    case available(FlexOutputPair)
    case monoDevice
    case noOutputs
    case pairUnavailable(Int)
    case deviceUnavailable

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Performer-facing explanation. No device identifier, path or plug-in state.
    var message: String {
        switch self {
        case .available(let pair):
            return "StageKeys mixes to \(pair.title)."
        case .monoDevice:
            return "This device reports one output channel, so it has no stereo pair. StageKeys mixes to the system output."
        case .noOutputs:
            return "This device reports no output channels. Choose another output or refresh Audio Devices."
        case .pairUnavailable(let index):
            return "\(FlexOutputPair(index: index).title) is not available on this device. Choose an available pair; StageKeys does not substitute another one."
        case .deviceUnavailable:
            return "The selected audio device does not report an output channel count. Refresh Audio Devices or choose another output."
        }
    }
}

enum FlexRouting {
    /// Usable stereo pairs from a device's reported output channel count. An
    /// odd trailing channel cannot carry a stereo pair by itself.
    static func pairs(channels: UInt32) -> [FlexOutputPair] {
        let usable = min(FlexOutputPair.maximumPairs, Int(channels / 2))
        return (0..<usable).map(FlexOutputPair.init(index:))
    }

    /// Output channels left over after pairing them all.
    static func unpairedChannels(_ channels: UInt32) -> Int { Int(channels % 2) }

    /// Resolve a requested pair index against the selected device. `nil` channels
    /// means the device's capability is unknown, which is reported as such.
    static func state(pair index: Int, channels: UInt32?) -> FlexRouteState {
        guard let channels else { return .deviceUnavailable }
        if channels == 0 { return .noOutputs }
        if channels == 1 { return .monoDevice }
        guard index >= 0 else { return .pairUnavailable(0) }
        let pairs = pairs(channels: channels)
        guard pairs.indices.contains(index) else { return .pairUnavailable(index) }
        return .available(pairs[index])
    }

    /// Bounded one-line capability summary for Settings and diagnostics.
    static func summary(channels: UInt32) -> String {
        let pairs = pairs(channels: channels)
        guard !pairs.isEmpty else {
            return channels == 0 ? "No output channels reported" : "One output channel; no stereo pair"
        }
        let listed = pairs.prefix(4).map(\.title).joined(separator: ", ")
        let more = pairs.count > 4 ? ", +\(pairs.count - 4) more" : ""
        let unpaired = unpairedChannels(channels)
        return "\(pairs.count) stereo pair\(pairs.count == 1 ? "" : "s"): \(listed)\(more)" +
            (unpaired == 1 ? " · 1 unpaired channel" : "")
    }
}
