import Foundation
struct SessionSettings: Codable {
    var selectedPatchID: UUID?
    var activeSnapshotID: UUID?
    var notesMode: Bool?
    var modWheel: Float?
    var master: Float = 0.7
    var reverb: Float = 22
    var transition: Float = 1.5
    var midiChannel = -1
    var primarySourceID: Int32?
    var secondarySourceID: Int32?
    var secondaryChannel: Int?
    var velocityMinimum: Int?
    var velocityMaximum: Int?
    var sourceNames: [Int32:String]?
    var disableSilent = false
    var showRanges = true
    var tonicGain: Float = 0.32
    var tonicBrightness: Float = 0.7
    var tonicShimmer: Float = 0
    var audioOutputUID: String?
    var activeSetlistID: UUID?
    var tonicSound:ExternalSound?
    var tonicVelocitySelector:Bool?
    var tonicTimbre:Int?
    var tonicLastRoot:Int?
    var tonicLocked:Bool?
    func validate() -> Bool {
        (0..<12).contains(tonicTimbre ?? 0) && (0..<12).contains(tonicLastRoot ?? 0) && (tonicSound == nil || tonicSound?.kind == .samplerPreset) && (audioOutputUID?.utf8.count ?? 0) <= 4096 && (modWheel.map { $0.isFinite && (0...1).contains($0) } ?? true) && (-1...15).contains(secondaryChannel ?? -1) && (0...127).contains(velocityMinimum ?? 0) && ((velocityMinimum ?? 0)...127).contains(velocityMaximum ?? 127) && (sourceNames?.count ?? 0) <= 512 && master.isFinite && (0...1).contains(master) && reverb.isFinite && (0...65).contains(reverb) && transition.isFinite && (0...15).contains(transition) && (-1...15).contains(midiChannel) && tonicGain.isFinite && (0...1).contains(tonicGain) && tonicBrightness.isFinite && (0...1).contains(tonicBrightness) && tonicShimmer.isFinite && (0...1).contains(tonicShimmer)
    }
}
