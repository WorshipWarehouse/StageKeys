#!/usr/bin/env python3
"""Fail when incoming MIDI pitch bend is dropped again (#3).

`Store.handleMIDI` accepted notes, controllers and program change but had no
0xE0 case, so a keyboard's pitch wheel never reached a hosted sampler or Audio
Unit. This gate checks the wire decoding, the primary-only dispatch, the
forwarded 0xE0 bytes, the recentring on Panic/Stop and the regression program's
registration in the hosted library job.
"""
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
errors = []


def fail(message):
    errors.append(message)


def read(path):
    return (repo / path).read_text()


target = read('Sources/MIDIControlTarget.swift')
store = read('Sources/Store.swift')
audio = read('Sources/AudioController.swift')
instruments = read('Sources/ExternalInstruments.swift')
shell = read('Tests/test-library.sh')
workflow = read('.github/workflows/distribution.yml')
changelog = read('CHANGELOG.md')
test_path = repo / 'Tests/MIDIPitchBendTests.swift'
doc_path = repo / 'Docs/MIDI-PITCH-BEND.md'

# Wire decoding: 14-bit value, reserved bit ignored, each half scaled by its own
# span so both extremes land on exactly ±1.
if 'enum MIDIPitchBend' not in target:
    fail('Sources/MIDIControllerTarget.swift no longer decodes pitch bend')
if 'static let centre = 8192' not in target:
    fail('the 14-bit pitch-bend centre is missing')
normalized = re.search(r'static func normalized\(lsb: UInt8, msb: UInt8\) -> Float \{(.*?)\n    \}', target, re.S)
if not normalized:
    fail('MIDIPitchBend.normalized(lsb:msb:) is missing')
else:
    body = normalized.group(1)
    if 'msb & 0x7f' not in body or 'lsb & 0x7f' not in body:
        fail('the reserved bit of a pitch-bend data byte is no longer masked')
    if 'delta >= 0 ? Float(delta) / 8191 : Float(delta) / 8192' not in body:
        fail('both halves of the wheel are no longer scaled by their own span')
encoded = re.search(r'static func bytes\(normalized: Float\) -> \(lsb: UInt8, msb: UInt8\) \{(.*?)\n    \}', target, re.S)
if not encoded:
    fail('MIDIPitchBend.bytes(normalized:) is missing')
else:
    body = encoded.group(1)
    if 'guard normalized.isFinite' not in body:
        fail('a non-finite wheel position is no longer recentred')
    if 'min(1, max(-1, normalized))' not in body:
        fail('an out-of-range wheel position is no longer clamped')

# The store accepts the wheel from the primary controller only, records it and
# forwards it. A secondary controller owns no notes.
dispatch = re.search(r'case 0xe0:(.*?)case 0xb0:', store, re.S)
if not dispatch:
    fail('Store.handleMIDI no longer handles pitch bend (0xE0)')
else:
    body = dispatch.group(1)
    if 'guard isPrimary else { return }' not in body:
        fail('a secondary controller can now bend the primary keyboard')
    if 'pitchBend = MIDIPitchBend.normalized(lsb: a, msb: b)' not in body:
        fail('the wheel position is no longer decoded into the published state')
    if 'audio.pitchBend(pitchBend)' not in body:
        fail('the accepted wheel position is no longer forwarded to the instruments')

if 'pitchBend = 0; audio.pitchBend(0)' not in store:
    fail('Panic no longer recentres the wheel')
if 'func pitchBend(_ normalized: Float) { externalRack?.pitchBend(normalized) }' not in audio:
    fail('AudioController no longer forwards the wheel to the hosted rack')

rack = re.search(r'func pitchBend\(_ normalized: Float\) \{(.*?)\n    \}', instruments, re.S)
helper = re.search(r'private func applyPitchBend\(_ channel:Int\) \{(.*?)\n    \}', instruments, re.S)
if not rack or 'applyPitchBend(channel)' not in rack.group(1):
    fail('the rack no longer applies the current bend to its installed voices')
if not helper or 'midi(channel,0xE0,bytes.lsb,bytes.msb)' not in helper.group(1):
    fail('the wheel is no longer delivered as an actual 0xE0 event')
if not helper or 'parallel.forEach' not in helper.group(1):
    fail('parallel imported branches no longer receive the wheel')
if 'if pitchBendSource == source' not in store:
    fail('the disconnected bend owner is no longer released')
if 'func pitchBend(_ lsb:UInt8,_ msb:UInt8)' not in instruments:
    fail('an imported branch no longer forwards the wheel to its sampler')

if not test_path.exists():
    fail('Tests/MIDIPitchBendTests.swift is missing')
else:
    program = test_path.read_text()
    for needle, why in [
        ('"a secondary controller cannot bend the primary keyboard"', 'secondary rejection is not asserted'),
        ('"Panic recentres the wheel"', 'Panic recentring is not asserted'),
        ('"input is clamped, never wrapped"', 'the clamp is not asserted'),
        ('"the rejected bend was forwarded anyway"', 'the rejected event reaching the rack is not asserted'),
    ]:
        if needle not in program:
            fail('the regression program no longer asserts that ' + why)

if 'MIDIPitchBendTests' not in shell:
    fail('Tests/test-library.sh no longer runs MIDIPitchBendTests')

if 'Tests/test-midi-pitch-bend.py' not in workflow:
    fail('.github/workflows/distribution.yml does not run this gate in the hosted job')

if not doc_path.exists():
    fail('Docs/MIDI-PITCH-BEND.md is missing')
else:
    doc = doc_path.read_text()
    if 'bend range' not in doc.lower():
        fail('the document no longer states that the instrument keeps its own bend range')
    if 'Synth.c' not in doc:
        fail('the document no longer records the native-synth limitation')

if '#3' not in changelog:
    fail('CHANGELOG.md no longer records the pitch-bend change under #3')

if errors:
    print('\n'.join('FAIL: ' + error for error in errors))
    raise SystemExit(1)
print('PASS: pitch bend is decoded, accepted only from the primary controller, forwarded as 0xE0 and recentred by Panic')
