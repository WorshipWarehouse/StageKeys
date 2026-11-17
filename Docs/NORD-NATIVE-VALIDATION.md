# Experimental native Nord piano import

Tracks #211–#216. StageKeys imports a **type-1 CBIN `.npno` piano**, verifies its
CRC32, reads the directory, and decodes selected attack recordings into managed
16-bit WAV files at 35002 Hz. A native Apple sampler preset and StageKeys map use
those recordings; no Nord application, Nord hardware, plugin or network is needed
for the converted instrument. This is a **partial translation**, not Nord engine
emulation or established sonic parity.

## User workflow

In Import Sounds choose **Instrument File**, then the authorized `.npno`. Review
its decoded PCM size and the complete differences. Choose **Convert Attack
Recordings** or **Discard**. Successful conversion adds one native instrument to
My Sounds. Add it to a rack layer normally. Cancel Import Before Commit stops
preparation and removes its uncommitted files. Inspecting or discarding adds no
catalog entry; duplicates are recognized by source SHA256 and keep existing edits.
The selected original file stays untouched; its hash accompanies conversion notes.
It is not bundled into the app or copied into a source archive.

Native instruments can use the existing personal `.stagekeyspack` export/import
workflow. Export is a user-initiated personal transfer, not a vendor-content license
or automatic cloud upload. Obtain the necessary content permissions for your use.
After copying a pack through Files/AirDrop to another Apple device, import it and
keep it downloaded for offline playback. Direct iPad `.npno` import is experimental
and shares the same software path; physical iPad memory/lifecycle qualification
is outstanding. Mac-prepared packs are the initial portable path.

## Mapping and differences

| Feature | Translation |
| --- | --- |
| Container versions | Read-only inspection: generation 0/1 and stream 0x450/0x464; decoding requires generation 1 and verified CRC32 |
| Sample codec | Signed low-bit-first residuals in big-endian words; predictor orders 0–4, widths 1–16; four seeds/channel; exact 64-frame block-overlap check |
| Source frames/stereo | Exact integer PCM, interleaved channels, no normalization or rate conversion during decode |
| Keys / roots | Each covered MIDI key uses the stored root map; uncovered keys stay silent |
| Velocity layers | V6 stored thresholds; V5 midpoint thresholds on the five-times scale; selection uses upstream Electro 5 Touch 0 measurements and interpolation, approximately ±2 MIDI velocities |
| Tuning | Signed per-key units × 0.7 cents; upstream measured estimate, not individual Nord hardware calibration |
| Gain | V6 library gain minus stroke trim, tenths dB, boost capped at 10.8 dB; V5 nonnegative integer dB trim; native limits refuse extreme values |
| Loops | Source start plus length becomes inclusive native end; out-of-frame loops refuse conversion |
| Pedal resonance / release banks | Counted and disclosed, not rendered in this attack-only conversion |
| Pedals / decay / note-off | Native sustain and 100 ms release substitute; source damper range, decay ladders, note-off fades, sympathetic resonance, crossfades, Nord effects and exact continuous velocity dynamics are not translated |
| Other formats / engines | `.nsmp*`, `.ns4p`, Nord synth/organ/effects and USB transfer are outside this implementation |

Limits: 512 MiB compressed input, 4096 strokes, 180 seconds per stroke, 1.5 GB
aggregate decoded PCM, 16384 mapped native zones. The file-size check precedes
reading; directory spans, total PCM size, root references and checksum precede
PCM allocation. Decoder checks count, signed reconstruction, clipping, overlap and
cancellation every block. Only one stroke's PCM is decoded at a time. Import does
not run on the audio callback. File reading, hashing, mapping, decoding and writing
run in background tasks; a small Apple template is acquired on the main thread.
The catalog uses the existing compare-and-commit transaction. Cancellation and
errors remove only the conversion's unique uncommitted assets.

## Reproducible checks

Public CI uses original synthetic fixtures only:

```sh
python3 Tests/run-local-library.py . /private/tmp/nord-generated-tests \
  NordPianoInspectionTests NordPianoDecodeTests NordNativeImportTests \
  TransactionalImportTests PersonalSoundPackTests
python3 Tests/test-library-gate.py
python3 Tests/test-distribution.py
Tools/verify-release.sh mac /private/tmp/nord-release-mac
Tools/verify-release.sh simulator /private/tmp/nord-release-simulator
```

The generated end-to-end test covers stereo, velocity boundaries, root/key tuning,
loops, cancellation rollback, native rack audio, catalog restart, duplicate identity,
pack relocation and matching rendered energy after relocation. Distribution gates
refuse `.npno` and `.nsmp*` assets and require the BSD notice in both app bundles.

For authorized private files, first build the verification core above, then compile
`Tools/NordPrivateAudit.swift` with testable access to that exact module. Example
(the output path must not exist):

```sh
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/nord-generated-tests/modules \
  -I /private/tmp/nord-generated-tests -L /private/tmp/nord-generated-tests \
  -lStageKeysVerificationCore -Xlinker -rpath -Xlinker /private/tmp/nord-generated-tests \
  -import-objc-header Sources/Bridge.h -disable-bridging-pch \
  Tools/NordPrivateAudit.swift -o /private/tmp/nord-private-audit
/private/tmp/nord-private-audit /private/tmp/NEW-private-nord-audit \
  '/path/to/authorized-piano-1.npno' '/path/to/authorized-piano-2.npno'
```

This local-only helper decodes **every bank**, checks repeated middle-C attack
PCM, uses the production Store preview/import, and renders low/middle/high notes at
five velocities through the native rack, offline at 48 kHz/512 frames. It verifies
unchanged input SHA256 and records PCM hashes, sizes, conversion times, energy,
peaks and process peak RSS. Its output directory contains private derived sounds:
**do not commit or upload it**. Offline energy is not listening or latency evidence.

## Recorded local results — 17 November 2026

Implementation revision `5223583e1a6923b939857b19e13cd80c6ff4c81f`, tree
`f396b62da36569df32d7a7e1af87e5166d3b252e`. Host: Mac16,10, 16 GiB RAM,
macOS 27.2 build 26B123, Xcode 27.2, arm64. No reference Nord hardware capture
was available. These checks use offline output, not an audible physical route.

- Complete default library regression: **133 passed, 11 private-fixture skips,
  0 failed**. Those skips are not exercised compatibility evidence. The optional
  private PianoHeldNote fixture also remains unexercised by the default run.
- Optimized current core, with assertions enabled in the test programs:
  **NordPianoDecodeTests and NordNativeImportTests passed**, zero skips/failures.
- Universal unsigned Mac and unsigned iOS Simulator Release artifact gates passed;
  distribution/content/document gates and the simulator icon gate passed. Both
  bundles include the BSD notice. Test registration and distribution refusal tests
  passed.
- Mac visual walkthrough on isolated app data and an original generated piano:
  Instrument File picker → size/features/differences preview → Convert Attack
  Recordings → one installed My Sounds entry. No existing user session was edited.
- Private audit used the exact current optimized core through the production Store
  import and native rack, at **48 kHz / 512 frames**, no effects, layer gain 0.65,
  master 0.1. Each piano rendered keys **36, 60, 96** at velocities
  **20, 57, 58, 100, 127**, 90 blocks per case plus release/tail blocks. All 30 cases
  had finite nonzero output. Every source stroke decoded, and every stored middle-C
  attack layer decoded repeatedly with identical PCM. Input hashes matched before
  and after. This is not a pitch/fidelity, audible-loop, hardware-latency or sustain
  pedal qualification.

| Private input | All decoded frames (per-channel frame counts summed across strokes) | Native zones | Converted PCM bytes | Diagnostic import time | All-bank PCM SHA256 (interleaved, native little-endian Int16, directory order) |
| --- | ---: | ---: | ---: | ---: | --- |
| Astoria Grand XL 6.1.npno | 197734068 | 995 | 352098600 | 5.63 s | `8499bc69f4a804e36ab6f88ef15680feb556d71c2068a32a2f4440892a003fdb` |
| EP9 Stockholm XL 6.0.npno | 222300678 | 1860 | 423086208 | 6.45 s | `cf931a23e2323b2861e17f2d71363621a4203d15e095150590ebdf0083f65c8d` |

Astoria uses all 589 attack recordings. Stockholm uses 1459 of its 1465 attack
recordings: six receive no distinct integer MIDI velocity under this Touch 0
threshold interpolation/selection. They remain in the untouched source; another
touch curve can select differently. This is part of the documented velocity
approximation, not proof that those recordings are redundant on every Nord.

The audit process peak resident set was **2,219,933,696 bytes (2.07 GiB)** across
both pianos, including source buffers, inspection, conversion and resident native
playback. Import timings are diagnostic only: builds/other workloads overlapped,
no repeated cold/warm controlled trials were run, and the helper's frame/hash
aggregation was not optimized. They are not realtime CPU/latency measurements or
supported-device memory ceilings. This footprint strengthens the need for #216's
physical iPad admission/residency tests. Private derived files and the full JSON
report remain outside the checkout; only sanitized numbers/hashes are recorded.

## Remaining physical qualification (#215 / #216)

The connected-device inventory on 17 November 2026 contained a physical iPhone,
but no iPad. No physical-device installation or provisioning was performed.
An unsigned universal Mac build or simulator build cannot close either live gate.

For the intended Mac rig, record exact app revision, Mac/OS, interface/driver,
MIDI controller/connection, route, sample rate/block size and gain. Listen across
low/middle/high registers, every velocity boundary, sustained loops, pedal
press/release and note releases. Compare with the same source on authorized Nord
hardware when available. Record cold/warm load time, peak resident memory,
realtime deadline/headroom, rapid switching, reconnect/recovery and all audible
differences. Do not treat muted output or offline render speed as qualification.

For a physical iPad, record model/RAM/iPadOS, app revision, audio/MIDI hardware,
route and gain. Install a Mac-prepared personal pack through Files/AirDrop; verify
manifest hashes, restart, disable networking and play. Compare the same MIDI
sequence with Mac, including velocity boundaries, loop/pedal behavior, sustained
polyphony, patch changes, interruption/background/resume, corrupt pack, cancellation
and storage-full rollback. Record memory ceiling and rejection behavior before
claiming a supported piano/device combination. Existing #4/#105/#113 gates still
apply. Both issues remain open until those measured, audible checks exist.
