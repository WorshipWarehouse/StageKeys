import Foundation
@main struct PluginEditorModelTests {
    static func main() {
        // A plug-in may declare nothing usable; the editor still needs a real area.
        assert(PluginEditorModel.declaredSize(width: 0, height: 0) == PluginEditorModel.minimumSize)
        assert(PluginEditorModel.declaredSize(width: -400, height: 12) == PluginEditorModel.minimumSize,
               "Negative declarations must fall back to the editor floor")
        assert(PluginEditorModel.declaredSize(width: .nan, height: .infinity) == PluginEditorModel.minimumSize,
               "Non-finite declarations must fall back to the editor floor")
        assert(PluginEditorModel.declaredSize(width: 1400, height: 900) == CGSize(width: 1400, height: 900))
        assert(PluginEditorModel.declaredSize(width: 640.5, height: 420.2) == CGSize(width: 641, height: 421),
               "Fractional declarations round up so no edge of the plug-in view is clipped")

        let compact = PluginEditorModel.compactMaximum
        let screen = CGSize(width: 1600, height: 1000)
        let oversized = CGSize(width: 1400, height: 900)
        assert(PluginEditorModel.displaySize(declared: oversized, available: screen, compactMaximum: compact, expanded: false) == compact,
               "Collapsed, an oversized editor stops at the compact sheet cap and scrolls")
        assert(PluginEditorModel.displaySize(declared: oversized, available: screen, compactMaximum: compact, expanded: true) == oversized,
               "Expanded, the editor gets its full declared size when the screen allows it")
        assert(PluginEditorModel.canExpand(declared: oversized, available: screen, compactMaximum: compact),
               "An editor larger than the collapsed cap must offer expansion")

        let small = CGSize(width: 650, height: 420)
        assert(PluginEditorModel.displaySize(declared: small, available: screen, compactMaximum: compact, expanded: false) == small)
        assert(!PluginEditorModel.canExpand(declared: small, available: screen, compactMaximum: compact),
               "Expanding a view that already fits must not offer a no-op")

        // A window smaller than the editor cannot give expanding anything back.
        let narrow = CGSize(width: 800, height: 600)
        assert(PluginEditorModel.displaySize(declared: oversized, available: narrow, compactMaximum: compact, expanded: false) == narrow)
        assert(PluginEditorModel.displaySize(declared: oversized, available: narrow, compactMaximum: compact, expanded: true) == narrow)
        assert(!PluginEditorModel.canExpand(declared: oversized, available: narrow, compactMaximum: compact),
               "Expansion is not offered when the window is already the limit")

        // Unknown available space means unconstrained, never a zero-sized sheet.
        assert(PluginEditorModel.displaySize(declared: oversized, available: .zero, compactMaximum: compact, expanded: false) == compact)
        assert(PluginEditorModel.displaySize(declared: oversized, available: .zero, compactMaximum: compact, expanded: true) == oversized)

        // iOS has no collapsed cap: the sheet already uses the available screen.
        assert(PluginEditorModel.displaySize(declared: oversized, available: .zero, compactMaximum: .zero, expanded: false) == oversized)
        assert(!PluginEditorModel.canExpand(declared: oversized, available: .zero, compactMaximum: .zero),
               "Without a collapsed cap there is nothing to expand to")

        assert(PluginEditorModel.needsScrolling(declared: oversized, displayed: compact))
        assert(!PluginEditorModel.needsScrolling(declared: small, displayed: small))
        assert(!PluginEditorModel.needsScrolling(declared: CGSize(width: 640.4, height: 420), displayed: CGSize(width: 640, height: 420)),
               "Sub-point differences are not scrolling")

        assert(PluginEditorModel.waitDeadline == 12 && PluginEditorModel.waitInterval == 0.1)
        assert(PluginEditorModel.attemptLimit == 120, "The wait deadline must equal attemptLimit * waitInterval")

        // Precedence: a block is reported first, a catalog reason second, and only
        // an unexplained wait becomes a timeout.
        assert(PluginEditorModel.diagnosis(blockedID: "0-1-2", unavailableReason: "Not installed", attempts: 500)
               == .blocked(componentID: "0-1-2"))
        assert(PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: "Not installed", attempts: 500)
               == .unavailable(reason: "Not installed"))
        assert(PluginEditorModel.diagnosis(blockedID: "", unavailableReason: "", attempts: 0) == nil,
               "Empty reasons report nothing")
        assert(PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: nil, attempts: 119) == nil,
               "The editor keeps waiting before its deadline")
        assert(PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: nil, attempts: 120) == .timedOut(seconds: 12))
        assert(PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: nil, attempts: 2, limit: 3) == nil)
        assert(PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: nil, attempts: 3, limit: 3) == .timedOut(seconds: 12))
        assert(PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: nil, attempts: 1, limit: 0) == .timedOut(seconds: 12),
               "A nonsensical limit must not disable the deadline")

        // Every report explains itself and offers only an action that can succeed.
        let blocked = PluginEditorModel.Diagnosis.blocked(componentID: "0-1-2")
        assert(blocked.message.lowercased().contains("blocked"))
        assert(!blocked.detail.isEmpty)
        assert(blocked.recovery == .allowBlocked(componentID: "0-1-2"))
        let unavailable = PluginEditorModel.Diagnosis.unavailable(reason: "This Audio Unit is not installed on this device.")
        assert(unavailable.message == "This Audio Unit is not installed on this device.")
        assert(!unavailable.detail.isEmpty)
        assert(unavailable.recovery == .none, "Reinstalling is not something the editor can retry")
        let timedOut = PluginEditorModel.Diagnosis.timedOut(seconds: 12)
        assert(timedOut.message.contains("12"))
        assert(!timedOut.detail.isEmpty)
        assert(timedOut.recovery == .retry)
        let noInterface = PluginEditorModel.Diagnosis.noInterface
        assert(!noInterface.message.isEmpty && !noInterface.detail.isEmpty)
        assert(noInterface.recovery == .none)

        print("PASS: AU editor sizing, expansion, scrolling, wait deadline and blocked/unavailable/timeout reporting")
    }
}
