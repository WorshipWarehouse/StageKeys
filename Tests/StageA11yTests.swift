import Foundation
@main struct StageA11yTests {
 static func main()throws {
  let white=StageA11y.Palette.white, black=StageA11y.Palette.black
  // WCAG anchors: black on white is 21:1, a colour against itself is 1:1, and the
  // ratio is symmetric. These pin the sRGB linearisation before any pair is judged.
  assert(abs(white.contrast(against: black)-21) < 0.001)
  assert(abs(StageA11y.Palette.panel.contrast(against: StageA11y.Palette.panel)-1) < 0.000001)
  assert(abs(StageA11y.Palette.raised.contrast(against: StageA11y.Palette.base)-StageA11y.Palette.base.contrast(against: StageA11y.Palette.raised)) < 0.000001)
  // Source-over compositing and alpha clamping: the values SwiftUI renders for
  // `.opacity(_:)`, not an independent colour model.
  assert(white.composited(over: black, alpha: 0.5)==StageRGB(0.5,0.5,0.5).composited(over: black, alpha: 1))
  assert(white.composited(over: black, alpha: 1.4)==white && black.composited(over: white, alpha: -1)==white)
  let half=white.composited(over: black, alpha: 0.5)
  // Exact halves are not #808080: 0.5 sRGB measures 5.2808:1 on black, while the
  // often-quoted 5.32 belongs to 128/255. Pin the composited value, not the hex one.
  assert(abs(half.contrast(against: black)-5.2808) < 0.001, "50 % white on black must measure 5.28:1")
  assert(StageA11y.Palette.base.isInGamut && StageA11y.Palette.selected.isInGamut)
  // The release palette is fixed here so a silent colour change has to update the
  // measured record in Docs/ACCESSIBILITY.md instead of slipping through.
  assert(StageA11y.Palette.base==StageRGB(0.065,0.071,0.11))
  assert(StageA11y.Palette.panel==StageRGB(0.14,0.15,0.21))
  assert(StageA11y.Palette.raised==StageRGB(0.23,0.26,0.36))
  assert(StageA11y.Palette.selected==StageRGB(0.64,0.76,0.94))
  // Every audited pair must clear its own minimum, and the audit cannot shrink.
  let pairs=StageA11y.auditedPairs
  assert(pairs.count==9, "the audited text pairs are a release record; add to the record, do not delete from it")
  for pair in pairs {assert(pair.ratio >= pair.minimum, "\(pair.name) measures \(pair.ratio):1, below \(pair.minimum):1")}
  assert(Set(pairs.map(\.name)).count==pairs.count)
  assert(pairs.allSatisfy{$0.foreground.isInGamut && $0.background.isInGamut})
  // The piano octave marker was the one text pair that failed: 40 % black on the
  // 88 % key measured 2.74:1. The shipped 60 % value clears 4.5:1, and this keeps
  // the failing value as a regression witness.
  let key=StageA11y.Palette.whiteKey
  let before=black.composited(over: key, alpha: 0.4).contrast(against: key)
  let shipped=black.composited(over: key, alpha: 0.6).contrast(against: key)
  assert(before < StageA11y.bodyTextContrast && shipped >= StageA11y.bodyTextContrast)
  assert(abs(before-2.74) < 0.01 && abs(shipped-5.26) < 0.01)
  // Readable type floor: the theme clamps through this, so a dense control cannot
  // ask for 8, 9 or 10 pt text any more.
  assert(StageA11y.minimumTextSize==11)
  assert([0.0,8,9,10,10.9].map{StageA11y.fontSize($0)}.allSatisfy{$0==11})
  assert(StageA11y.fontSize(11)==11 && StageA11y.fontSize(14)==14 && StageA11y.fontSize(17.5)==17.5)
  assert(!StageA11y.meetsTextSize(10) && StageA11y.meetsTextSize(11))
  // Hit targets: 44 pt on touch, 28 pt for the pointer. The dense mixer icon
  // buttons are 34-38 wide, which passes the pointer target and is recorded as an
  // open touch-target item rather than silently treated as compliant.
  assert(StageA11y.minimumTouchTarget==44 && StageA11y.minimumPointerTarget==28)
  assert(StageA11y.meetsHitTarget(width: 44, height: 44, pointer: false))
  assert(!StageA11y.meetsHitTarget(width: 34, height: 45, pointer: false))
  assert(StageA11y.meetsHitTarget(width: 34, height: 45, pointer: true))
  assert(!StageA11y.meetsHitTarget(width: 27, height: 28, pointer: true))
  assert(StageA11y.meetsHitTarget(width: 28, height: 28, pointer: true))
  // Layer identity hues: two of the five measure 3.03:1 (blue) and 3.41:1 (purple)
  // as text on a panel, so the text colour has to be derived, not reused raw. The
  // fills, borders and icons keep the original hue.
  let accents=StageA11y.Palette.accents, panel=StageA11y.Palette.panel
  assert(accents.count==5)
  assert(accents[0]==StageRGB(0.97,0.66,0.28) && accents[1]==StageRGB(0.2,0.77,0.47) && accents[2]==StageRGB(0.24,0.39,0.94))
  assert(abs(accents[2].contrast(against: panel)-3.03) < 0.01, "blue is the recorded 3.03:1 text failure")
  assert(abs(accents[3].contrast(against: panel)-3.41) < 0.01, "purple is the recorded 3.41:1 text failure")
  let accentPairs=StageA11y.auditedAccentText
  assert(accentPairs.count==accents.count)
  for pair in accentPairs {assert(pair.meetsMinimum, "\(pair.name) measures \(pair.ratio):1")}
  for (index, accent) in accents.enumerated() {
    let raised=StageA11y.legibleAccent(accent, on: panel)
    assert(raised==StageA11y.legibleAccent(accent, on: panel), "the derivation must be deterministic")
    assert(raised.isInGamut && raised.contrast(against: panel) >= StageA11y.bodyTextContrast)
    // A hue that already reads is returned untouched; a failing hue is lightened.
    if accent.contrast(against: panel) >= StageA11y.bodyTextContrast {assert(raised==accent)} else {assert(raised != accent && raised.relativeLuminance > accent.relativeLuminance)}
    assert(abs(raised.contrast(against: panel)-accentPairs[index].ratio) < 0.000001)
  }
  print("PASS: contrast math, palette record, \(pairs.count) audited pairs, \(accentPairs.count) legible accents, octave-marker regression, readable-size floor and hit targets")
 }
}
