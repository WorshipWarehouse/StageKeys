import Foundation

/// The measured accessibility baseline for StageKeys' own release visual identity.
///
/// Only Foundation is imported: the palette, the WCAG 2.1 contrast math and the
/// type floors compile and are asserted on a machine without SwiftUI or Xcode.
/// `StageTheme` is the single renderer of these values, so a change here reaches
/// every surface at once and cannot drift away from the audited numbers.
enum StageA11y {
    /// StageKeys uses 11 pt as its initial dense-layout text floor. The
    /// theme clamps every requested size, so a dense control cannot ask for less.
    static let minimumTextSize: Double = 11
    /// Project audit thresholds: 44 pt on touch platforms, 28 pt for the pointer.
    static let minimumTouchTarget: Double = 44
    static let minimumPointerTarget: Double = 28
    /// WCAG 2.1 AA: 4.5:1 for body text, 3:1 for large text and UI components.
    static let bodyTextContrast: Double = 4.5
    static let largeTextContrast: Double = 3

    static func fontSize(_ requested: Double) -> Double {max(requested, minimumTextSize)}
    static func meetsTextSize(_ requested: Double)->Bool {requested >= minimumTextSize}
    static func meetsHitTarget(width: Double, height: Double, pointer: Bool)->Bool {
        let minimum=pointer ? minimumPointerTarget:minimumTouchTarget
        return width >= minimum && height >= minimum
    }
    /// One star in a five-star rating row. The drawn glyph is an icon, not the
    /// target: only its tappable box grows, and touch needs more room than a
    /// pointer. The shipped library control sized each star 17×28 pt, which
    /// missed even the pointer minimum.
    static func ratingStarTarget(touch: Bool)->Double {touch ? minimumTouchTarget:minimumPointerTarget}

    /// The audited box for the workspace strip's icon buttons (sustain, layer
    /// ranges, keyboard ranges). Touch platforms take the touch minimum; a mouse
    /// pointer keeps the compact dense box, which still clears the pointer one.
    static func workspaceButtonTarget(touch: Bool)->Double {touch ? minimumTouchTarget:30}

    /// Dense icon buttons that shipped with a fixed box narrower or shorter than
    /// the audited touch minimum: the Tonic pad's power and patch-lock boxes, the
    /// mixer's sound-settings and effect-bypass buttons, four transport boxes, the
    /// MIDI Learn close button, the library sort button and the +/- number steppers.
    /// Each keeps its shipped size for the pointer and takes the touch minimum on
    /// iPhone/iPad, so no view carries a threshold of its own.
    enum DenseControl: String, CaseIterable {
        case tonicPower, tonicPatchLock, mixerSoundSettings, midiEffectBypass, audioEffectBypass
        case metronome, countIn, importSounds, mainMenu, midiLearnClose, librarySort, numberStepper
        /// The size the control shipped with, measured from the source at the
        /// audit and kept here as the failing witness and the pointer size.
        var shippedWidth: Double {
            switch self {
            case .tonicPower, .metronome: return 38
            case .tonicPatchLock, .mainMenu: return 40
            case .mixerSoundSettings, .midiEffectBypass, .countIn: return 34
            case .audioEffectBypass, .numberStepper: return 36
            case .importSounds, .midiLearnClose, .librarySort: return 30
            }
        }
        var shippedHeight: Double {
            switch self {
            case .tonicPower, .tonicPatchLock: return 46
            case .mixerSoundSettings: return 45
            case .midiEffectBypass, .audioEffectBypass: return 49
            case .metronome, .countIn: return 44
            case .importSounds, .mainMenu: return 36
            case .midiLearnClose: return 30
            case .librarySort, .numberStepper: return 42
            }
        }
    }

    /// True where the audited touch minimum applies (iPhone and iPad).
    static var touchTargetsApply: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// The rendered box for a dense control: the touch minimum on touch, and the
    /// shipped size with the pointer, lifted to the pointer minimum if it is under.
    static func denseWidth(_ control: DenseControl, touch: Bool)->Double {
        max(touch ? minimumTouchTarget:minimumPointerTarget, control.shippedWidth)
    }
    static func denseHeight(_ control: DenseControl, touch: Bool)->Double {
        max(touch ? minimumTouchTarget:minimumPointerTarget, control.shippedHeight)
    }
    static func denseWidth(_ control: DenseControl)->Double {denseWidth(control, touch: touchTargetsApply)}
    static func denseHeight(_ control: DenseControl)->Double {denseHeight(control, touch: touchTargetsApply)}

    /// The release palette. These are the only colour definitions: `StageTheme`
    /// builds SwiftUI colours from them instead of carrying its own copies.
    enum Palette {
        static let base=StageRGB(0.065, 0.071, 0.11)
        static let panel=StageRGB(0.14, 0.15, 0.21)
        static let raised=StageRGB(0.23, 0.26, 0.36)
        static let selected=StageRGB(0.64, 0.76, 0.94)
        static let white=StageRGB(1, 1, 1)
        static let black=StageRGB(0, 0, 0)
        /// Unpressed button fill: `raised` at 65 % over `base`.
        static var buttonFill:StageRGB {raised.composited(over: base, alpha: 0.65)}
        /// The white piano key and its octave label.
        static let whiteKey=StageRGB(0.88, 0.88, 0.88)
        static let blackKey=StageRGB(0.07, 0.07, 0.07)
        /// Layer identity hues, in layer order. `StageTheme.colors` renders these
        /// first and only then falls back to system colours.
        static let accents:[StageRGB] = [StageRGB(0.97, 0.66, 0.28), StageRGB(0.2, 0.77, 0.47),
                                         StageRGB(0.24, 0.39, 0.94), StageRGB(0.59, 0.34, 0.90),
                                         StageRGB(0.88, 0.40, 0.75)]
    }

    /// Raise an identity hue toward white until it clears the required ratio on the
    /// surface it is drawn on. Fills, borders and icons keep the original hue; this
    /// exists because two layer accents measure 3.03:1 and 3.41:1 as text on a panel.
    static func legibleAccent(_ accent:StageRGB, on surface:StageRGB, minimum:Double = bodyTextContrast)->StageRGB {
        if accent.contrast(against: surface) >= minimum {return accent}
        for step in 1...20 {
            let t=Double(step)/20
            let raised=StageRGB(accent.red+(1-accent.red)*t, accent.green+(1-accent.green)*t, accent.blue+(1-accent.blue)*t)
            if raised.contrast(against: surface) >= minimum {return raised}
        }
        return surface.contrast(against: Palette.white) >= minimum ? Palette.white : surface
    }

    /// Accent colours as *text* on the panel surface: the identity hue where it
    /// already reads, raised toward white where it does not.
    static var auditedAccentText:[StageTextPair] {
        Palette.accents.enumerated().map { index, accent in
            StageTextPair(name: "Layer \(index+1) accent text on a panel",
                          foreground: legibleAccent(accent, on: Palette.panel),
                          background: Palette.panel, alpha: 1, minimum: bodyTextContrast)
        }
    }

    /// Selected text/background pairs from the release surfaces, with the ratio it must
    /// keep. The test asserts the measured ratio; `Docs/ACCESSIBILITY.md` records
    /// the same numbers, so a palette edit that drops below a threshold fails a
    /// gate instead of quietly reducing legibility.
    static var auditedPairs:[StageTextPair] {
        let button=Palette.buttonFill
        return [
            StageTextPair(name: "Primary label on the app background",
                          foreground: Palette.white, background: Palette.base, alpha: 0.9, minimum: bodyTextContrast),
            StageTextPair(name: "Primary label on a panel",
                          foreground: Palette.white, background: Palette.panel, alpha: 0.9, minimum: bodyTextContrast),
            StageTextPair(name: "Primary label on a raised surface",
                          foreground: Palette.white, background: Palette.raised, alpha: 0.9, minimum: bodyTextContrast),
            StageTextPair(name: "Button label on the default button fill",
                          foreground: Palette.white, background: button, alpha: 0.9, minimum: bodyTextContrast),
            StageTextPair(name: "Selected button label on the selection fill",
                          foreground: Palette.base, background: Palette.selected, alpha: 1, minimum: bodyTextContrast),
            StageTextPair(name: "Accent value text on a panel",
                          foreground: Palette.selected, background: Palette.panel, alpha: 1, minimum: bodyTextContrast),
            StageTextPair(name: "Secondary label on a panel",
                          foreground: Palette.white, background: Palette.panel, alpha: 0.6, minimum: bodyTextContrast),
            StageTextPair(name: "Piano octave label on a white key",
                          foreground: Palette.black, background: Palette.whiteKey, alpha: 0.6, minimum: bodyTextContrast),
            StageTextPair(name: "Selected key and Tonic root fill against the background",
                          foreground: Palette.selected, background: Palette.base, alpha: 1, minimum: largeTextContrast)
        ]
    }
}

/// An sRGB colour with the WCAG 2.1 relative-luminance and contrast-ratio math.
struct StageRGB:Equatable {
    var red:Double, green:Double, blue:Double
    init(_ red:Double,_ green:Double,_ blue:Double) {self.red=red;self.green=green;self.blue=blue}
    var isInGamut:Bool {(0...1).contains(red) && (0...1).contains(green) && (0...1).contains(blue)}
    /// Source-over compositing of a translucent foreground on an opaque background,
    /// which is what SwiftUI renders for `.opacity(_:)` text and fills.
    func composited(over background:StageRGB, alpha:Double)->StageRGB {
        let a=min(1, max(0, alpha))
        return StageRGB(a*red+(1-a)*background.red, a*green+(1-a)*background.green, a*blue+(1-a)*background.blue)
    }
    private static func linear(_ channel:Double)->Double {
        let c=min(1, max(0, channel))
        return c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055, 2.4)
    }
    var relativeLuminance:Double {
        0.2126*Self.linear(red)+0.7152*Self.linear(green)+0.0722*Self.linear(blue)
    }
    func contrast(against other:StageRGB)->Double {
        let first=relativeLuminance, second=other.relativeLuminance
        return (max(first, second)+0.05)/(min(first, second)+0.05)
    }
}

/// One audited text/background pair: the required ratio travels with the values so
/// the documentation, the renderer and the test cannot disagree.
struct StageTextPair {
    let name:String
    let foreground:StageRGB
    let background:StageRGB
    let alpha:Double
    let minimum:Double
    var ratio:Double {foreground.composited(over: background, alpha: alpha).contrast(against: background)}
    var meetsMinimum:Bool {ratio >= minimum}
}
