import Foundation
import AVFoundation
import AudioToolbox

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
    var nativeSampler:NativeSamplerProgram?
}


/// Converted instruments use resident samples on Mac: the streamed multi-bank
/// graph can introduce discontinuities absent from offline/resident playback.
/// Only active instruments are loaded; original sample files remain untouched.
enum SamplerRendering {
    static func configure(_ sampler:AVAudioUnitSampler,offline:Bool,resident:Bool=false)throws {
        var properties:[(AudioUnitPropertyID,UInt32)]=[]
        if offline {properties.append((kAudioUnitProperty_OfflineRender,UInt32(1)))}
        #if os(macOS)
        if offline || resident {properties.insert((kMusicDeviceProperty_StreamFromDisk,0),at:0)}
        #endif
        for (property,value) in properties {
            var setting=value
            let status=AudioUnitSetProperty(sampler.audioUnit,property,kAudioUnitScope_Global,0,&setting,UInt32(MemoryLayout<UInt32>.size))
            guard status==noErr else{throw NSError(domain:NSOSStatusErrorDomain,code:Int(status))}
        }
    }
}
