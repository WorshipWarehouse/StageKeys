# Accessibility and visual-identity baseline

Issue #19 asks for StageKeys' own release visual identity with an audit of contrast, minimum
readable text, keyboard navigation, VoiceOver labels, touch targets, focus and scaling, and for
responsive evidence on Mac and physical iPad/iPhone. This record covers the measurable part of
that audit: the palette, text sizes and hit targets are now defined once, measured, and gated.
Interactive evidence (VoiceOver order, keyboard focus, rotation, split view) still needs a Mac and
physical devices — see [Not verified here](#not-verified-here).

## What changed

| Before | After |
| --- | --- |
| Palette literals lived in `StageTheme`; nothing could check them | `StageA11y.Palette` is the only definition; `StageTheme` renders it |
| Text as small as 8–10 pt in the mixer, transport, editors and import surface | Every themed size is clamped to **11 pt**; the 8–10 pt call sites were raised |
| Piano octave marker at 40 % black on the 88 % key (**2.74:1**) | 60 % black (**5.26:1**); the failing value stays in the test as a witness |
| No stated touch/pointer target, no record | 44 pt touch / 28 pt pointer constants, measured against the dense controls |
| Contrast unmeasured | 9 audited text/background pairs asserted in a gated test |

## Measured contrast

Ratios are WCAG 2.1 relative-luminance values computed from the sRGB components the app renders,
including source-over compositing of translucent text and the 65 % button fill. They are not
screenshot samples: a screenshot adds display profile and gamma, which this Linux pass cannot
calibrate.

| Pair | Ratio | Required | Result |
| --- | --- | --- | --- |
| Primary label on the app background (white 90 %, `base`) | 15.12:1 | 4.5:1 | pass |
| Primary label on a panel (white 90 %, `panel`) | 12.34:1 | 4.5:1 | pass |
| Primary label on a raised surface (white 90 %, `raised`) | 8.38:1 | 4.5:1 | pass |
| Button label on the default button fill (white 90 %, `raised` 65 % over `base`) | 10.69:1 | 4.5:1 | pass |
| Selected button label (`base` on `selected`) | 10.22:1 | 4.5:1 | pass |
| Accent value text on a panel (`selected` on `panel`) | 8.19:1 | 4.5:1 | pass |
| Secondary label on a panel (white 60 %, `panel`) | 6.32:1 | 4.5:1 | pass |
| Piano octave label on a white key (black 60 %, key 88 %) | 5.26:1 | 4.5:1 | pass (was 2.74:1) |
| Selected key and Tonic root fill (`selected` on `base`) | 10.22:1 | 3:1 | pass |

The exported digests, reading order, colour values and ratios are asserted by
`Tests/StageA11yTests.swift`; `Tests/test-accessibility-audit.py` additionally fails when a view
renders `Text` below 11 pt or when `StageTheme` stops routing through the baseline.

## Layer accent text

The five layer identity hues carry fills, borders, icons and the rack-effects row label. Two do
not read as text on `panel`: blue measures **3.03:1** and purple **3.41:1**. Fills and icons keep the
original hue (blue still clears the 3:1 graphical-object minimum); text uses
`StageA11y.legibleAccent`, which raises the hue toward white by the smallest 5 % step that clears
4.5:1. The derivation is deterministic and asserted, so the identity hue and the rendered text
colour stay tied to one record.

| Layer | Identity hue on `panel` | Text colour on `panel` |
| --- | --- | --- |
| 1 amber | 7.59:1 | 7.59:1 (unchanged) |
| 2 green | 6.64:1 | 6.64:1 (unchanged) |
| 3 blue | 3.03:1 | 4.70:1 |
| 4 purple | 3.41:1 | 4.72:1 |
| 5 pink | 4.86:1 | 4.86:1 (unchanged) |

Layers past the five custom accents use the audited `selected` accent for text, because a system
colour's components cannot be measured from code.

Not measured: SwiftUI system colours (`.secondary`, `.tertiary`, `.primary`) and the audio-meter
gradients. System colours are resolved by the platform per appearance and cannot be sampled
without a running app; the one 9 pt `.tertiary` reading (`−∞` under each fader) was moved to
`.secondary` so it depends only on an increasing-opacity system style.

## Readable text sizes

`StageTheme.font(_:)` clamps through `StageA11y.fontSize(_:)`, so 8, 9 or 10 pt cannot render even
if a new call site asks for it. The call sites that were already below the floor were raised
explicitly, because `.system(size:)` bypasses the theme:

- Mixer and transport: "Tonic Pad", "Patch/Lock", "Play In", "Hear In", "Midi", "Audio 01–03",
  the rack-effects row, both dB readouts, and the rotary titles.
- Editors: effect/unit labels, the numbered slot badge, the output-note buttons, the EQ unit label.
- MIDI Learn: the target title and the `CC`/`Unassigned`/`Listening` status.
- Import: the `IMPORT FROM` heading and each source card's detail line.
- Snapshots: the beats/`Default` line.

Two dense readouts needed more room at 11 pt, so their columns widened: the Tonic fader column
44 → 52 pt and the layer dB column 45 → 52 pt, both with `lineLimit(1)`. The snapshot slot grew
28 → 34 pt to hold two 11 pt lines. These are the only layout dimensions changed; **the resulting
reflow has not been seen running** (see below).

### Documented exception

One line stays below the floor: the **piano octave marker is decorative and sized to the key width**
(`Text("C\(note/12-1)")` on the white keys). The key itself carries `.accessibilityLabel("C3")` and
`.isButton`, so the glyph is an orientation aid rather than the only source of the information,
and an 11 pt label would not fit the ~21 pt key at the default window width. Its contrast was still
raised to the audited 5.26:1. `Tests/test-accessibility-audit.py` checks this sentence exists here
before it allows the exemption.

## Touch and pointer targets

Constants: 44 pt for touch platforms, 28 pt for the pointer (`StageA11y.minimumTouchTarget` /
`minimumPointerTarget`), asserted in `StageA11yTests`.

Measured from the source at the audited surfaces: the dense mixer icon buttons are 34–38 pt wide by
45–49 pt high, the Tonic power/settings/lock buttons 38–40 × 46, and the snapshot card
100 × 34. Every one clears the 28 pt pointer minimum, so these controls clear the project's pointer-size threshold (not a claim of macOS accessibility compliance); on iPhone/iPad the
34–38 pt widths are below 44 pt. Widening them reflows the mixer that the issue also requires
photographic evidence for, so that change is deliberately left to the device pass rather than
guessed at from Linux.

## Reproduce

```bash
python3 Tests/test-accessibility-audit.py                  # floor, single palette, record
Tests/test-library.sh StageA11yTests                       # macOS: contrast + floors
python3 Tests/run-local-library.py . /private/tmp/a11y StageA11yTests
```

The baseline file imports only Foundation, so the same numbers can be compiled and asserted on
Linux without SwiftUI:

```bash
swiftc -O Sources/StageA11y.swift Tests/StageA11yTests.swift -o /tmp/a11y && /tmp/a11y
```

## Not verified here

This pass ran on Linux. The following remain open for the macOS/device review and are **not**
claimed as verified:

- Compiling the edited views (`StageKeysApp.swift`, `PerformanceControls.swift`, `Editors.swift`,
  `EqualizerEditor.swift`, `MIDIControlLearnView.swift`, `SoundImportView.swift`) — no SwiftUI or
  Xcode here; the Swift files were parse-checked only.
- Visual confirmation that the 11 pt labels and the widened fader/dB columns do not clip at
  1194 × 866, 1440 × 900, full screen, Mac split view, iPad landscape/portrait/split and iPhone
  compact widths.
- Dynamic Type and accessibility text scaling on iOS (`StageTheme.font` is a fixed custom font, so
  it does not grow; this is unchanged behaviour and still open).
- VoiceOver reading order and labels, keyboard focus order and `Tab` navigation, and Reduce
  Transparency/Increase Contrast behaviour.
- Whether the 34–38 pt touch targets above need widening, with the resulting reflow.

## macOS audit correction

The initial PR omitted StageA11y.swift from both committed Xcode targets, although the standalone library runner compiled it. It is now registered in both targets and the Python source audit is included in hosted processing CI. The 11 pt floor and 28 pt pointer threshold are project audit policies, not proof of universal readability or accessibility compliance. Ratios above cover selected source-color pairs, not every rendered state.
