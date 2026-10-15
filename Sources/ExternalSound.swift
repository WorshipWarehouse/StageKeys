import Foundation

/// Persisted, portable component identity; installation remains a device requirement.
struct ExternalAUIdentity: Codable, Hashable, Identifiable {
    var type: UInt32
    var subtype: UInt32
    var manufacturer: UInt32
    var name: String
    var id: String { "\(type)-\(subtype)-\(manufacturer)" }
}

struct ExternalSound: Codable, Hashable {
    enum Kind: String, Codable { case soundBank, sample, samplerPreset, audioUnit }
    var kind: Kind
    var name: String
    var fileName: String? = nil
    var component: ExternalAUIdentity? = nil
    var program: UInt8 = 0
    var bankMSB: UInt8 = 121
    var bankLSB: UInt8 = 0
}

