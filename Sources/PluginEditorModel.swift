import Foundation

/// Presentation rules for the hosted Audio Unit editor.
///
/// `PluginInterface` only renders what this returns: how large the plug-in's own
/// view is, whether the sheet can expand to the window, and how a plug-in that
/// never becomes ready is reported. Keeping these rules free of SwiftUI,
/// AVFoundation and Core Audio lets them be verified without a Mac, an Xcode
/// build or a third-party plug-in installed.
enum PluginEditorModel {
    /// Smallest area handed to a plug-in view, matching the sheet's own floor.
    static let minimumSize = CGSize(width: 320, height: 360)
    /// Collapsed sheet cap. A sheet is bounded by the host window slot, so an
    /// editor larger than this starts scrolling and gains from expanding.
    static let compactMaximum = CGSize(width: 1000, height: 700)
    /// The rack blocks a plug-in that has not instantiated within ten seconds.
    /// The editor polls slightly longer so it can report that block instead of a
    /// guess about why nothing appeared.
    static let waitDeadline: TimeInterval = 12
    static let waitInterval: TimeInterval = 0.1
    static var attemptLimit: Int { max(1, Int((waitDeadline / waitInterval).rounded())) }

    /// Sanitises the size a plug-in reports. Plug-ins may declare zero, negative,
    /// NaN or infinite content sizes; none of those may produce an unusable sheet.
    static func declaredSize(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: usable(width, floor: minimumSize.width), height: usable(height, floor: minimumSize.height))
    }

    /// The area the plug-in view gets. `available` is the host window space and is
    /// treated as unconstrained when it is unknown (zero) or nonsensical; a
    /// `compactMaximum` of zero means there is no collapsed cap at all.
    static func displaySize(declared: CGSize, available: CGSize, compactMaximum: CGSize, expanded: Bool) -> CGSize {
        let cap = expanded ? CGSize.zero : compactMaximum
        return CGSize(width: bounded(declared.width, cap: cap.width, available: available.width),
                      height: bounded(declared.height, cap: cap.height, available: available.height))
    }

    /// True only when expanding actually reveals more of the plug-in, so the
    /// control never offers a no-op.
    static func canExpand(declared: CGSize, available: CGSize, compactMaximum: CGSize) -> Bool {
        displaySize(declared: declared, available: available, compactMaximum: compactMaximum, expanded: true) !=
            displaySize(declared: declared, available: available, compactMaximum: compactMaximum, expanded: false)
    }

    /// Whether part of the plug-in view is outside the area it was given.
    static func needsScrolling(declared: CGSize, displayed: CGSize) -> Bool {
        declared.width > displayed.width + 0.5 || declared.height > displayed.height + 0.5
    }

    /// The action a reported problem offers, if any.
    enum Recovery: Equatable {
        case retry
        case allowBlocked(componentID: String)
        case none
    }

    /// Why a plug-in editor is not showing its interface. Reported instead of an
    /// open-ended spinner, and never guessed from a message string.
    enum Diagnosis: Equatable {
        case blocked(componentID: String)
        case unavailable(reason: String)
        case timedOut(seconds: Int)
        case noInterface

        var message: String {
            switch self {
            case .blocked:
                return "This instrument is blocked after a failed or interrupted load."
            case .unavailable(let reason):
                return reason
            case .timedOut(let seconds):
                return "The instrument did not become ready within \(seconds) seconds."
            case .noInterface:
                return "This instrument does not provide a custom interface or editable parameters."
            }
        }

        var detail: String {
            switch self {
            case .blocked:
                return "StageKeys stops retrying a plug-in that failed to load. Allow it again here, or from Sound Settings, to try this instrument once more."
            case .unavailable:
                return "Install a compatible version of this instrument, then reopen its interface. The saved sound and its settings are kept."
            case .timedOut:
                return "The plug-in may still be starting, or it may be waiting for its authorization or license window. Retry, or check the plug-in outside StageKeys."
            case .noInterface:
                return "No editable interface was returned. Check the instrument's documentation for other supported editing options."
            }
        }

        var recovery: Recovery {
            switch self {
            case .blocked(let componentID): return .allowBlocked(componentID: componentID)
            case .timedOut: return .retry
            case .unavailable, .noInterface: return .none
            }
        }
    }

    /// The current problem, in precedence order: a blocked plug-in is never
    /// masked by a stale catalog reason, a known unavailability outranks elapsed
    /// time, and only an unexplained wait becomes a timeout. `nil` while the
    /// editor is still legitimately waiting.
    static func diagnosis(blockedID: String?, unavailableReason: String?, attempts: Int,
                          limit: Int = attemptLimit) -> Diagnosis? {
        if let blockedID, !blockedID.isEmpty { return .blocked(componentID: blockedID) }
        if let unavailableReason, !unavailableReason.isEmpty { return .unavailable(reason: unavailableReason) }
        if attempts >= max(1, limit) { return .timedOut(seconds: Int(waitDeadline.rounded())) }
        return nil
    }

    private static func usable(_ value: CGFloat, floor: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return floor }
        return max(floor, value.rounded(.up))
    }

    private static func bounded(_ value: CGFloat, cap: CGFloat, available: CGFloat) -> CGFloat {
        var result = value.isFinite ? max(0, value) : 0
        if cap.isFinite, cap > 0 { result = min(result, cap) }
        if available.isFinite, available > 0 { result = min(result, available) }
        return result
    }
}
