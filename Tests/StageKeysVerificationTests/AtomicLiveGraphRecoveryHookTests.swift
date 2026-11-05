// Compile-time hook for the live-graph recovery diagnostic test suite.
//
// This file exists to carry a testable import so the release verification
// target can compile against the new fault-injection and graph-completion
// failure paths without requiring a full runtime reproduction here.
//
// Real AVFAudio -1 reproduction remains an acceptance item for the issue
// and is intentionally not claimed by this PR.

@testable import StageKeysVerificationCore
import Foundation

enum AtomicLiveGraphRecoveryHook {
    /// Placeholder compile check for the new hook surface.
    /// The real validation is in Docs and the issue acceptance criteria.
    static func compileCheck() -> Bool {
        return true
    }
}
