# Reference behavior matrix

Baseline: 2 November 2026. Installed bundle metadata verifies Sunday Keys **2.5.2 (3367)** and MainStage **4.3.1 (5233)**. Metadata does not verify current account entitlements. Prior repository observations document signed-in Sunday Keys Demo Mode on 13 and 30 October; Demo/Prime limitations remain in force for planning unless directly observed otherwise.

## Evidence rules and available tools

VERIFIED below is qualified as metadata, source or test; it never means a reference interaction was observed merely because it was documented. DOCUMENTED rows cite prior UI observations or current first-party manuals. INFERRED rows are proposals. UNKNOWN rows need access or measurement. Functional, visual, audio and persistence evidence must be tracked independently.

The installed REA CLI is 6.7.0. MCP tools are absent. Its CLI catalog lacks the older documented `inspect-desktop-application` operation; invoking that help returned the global catalog, not a target result. `doctor --client codex --json` required normal cache access, then reported Codex configuration drift, Hopper present and Ghidra/IDA unavailable. No configuration repair or new engine installation was made. `inspect-macho` was selected for bounded static target identity. Static inspection succeeded with evidence ID `ev_95b7ab92f4046760aa7e0b9f07b34a335ab7134d11220b2c03655a5e8d8b43b6`, universal x86_64/arm64 inventory and SHA-256 `501f35cc48b4d897b76875faca6b0f8b4b1477a686bd4409476e40fef3288c86`. Complete raw output stays in /private/tmp; retained summaries and SHA-256 are in EVIDENCE/verification. This cannot establish effects, snapshots or saved-state semantics. Installed skill/upstream capabilities must not be assumed to exist in this older CLI.

The current native computer-use attempt `cua.getApp("Sunday Keys")` timed out (-10005). No successful screenshot or runtime action sequence was captured. Therefore this session adds **no newly verified reference UI/audio behavior**. The current matrix deliberately carries prior observations as DOCUMENTED and supplies a resumable observation protocol.

## Comparison

| Surface | Reference evidence and scope | StageKeys source/test evidence | Difference and required check | Classification / owner |
| --- | --- | --- | --- | --- |
| Main navigation, Notes/Effects | DEEP-UI-AUDIT: 1194×866 layout, segmented view, 15 modules | StageKeysApp/PerformanceControls; Store/AllSoundSlots tests | Visual geometry, clipping, compact essential actions unmeasured | DOCUMENTED reference; VERIFIED source; #18/#19 |
| Layer ranges/reorder | Prior reverse-order overlay; endpoint drags not exercised on 13 Oct | LayerRangeEditor and store reorder/range tests | Gestures, overlap, range-vs-generated MIDI semantics | DOCUMENTED/UNKNOWN; #16/#11 |
| Instrument settings | First-party Sounds manual and prior eight-band EQ/compressor UI | ChannelSettings, SoundSettingsControls, NativeSoundOrder tests | Native vs imported/AU order; conditional envelope support | DOCUMENTED reference; VERIFIED source; #112 |
| Sound add/replace | Prior library selector/facets; explicit replace/cancel | SoundBrowser labels destination, cleanup; PR #119 model tests | Tag context edits persist independently; Cancel is not undo for prior explicit tag edits | DOCUMENTED reference; VERIFIED source; #17 |
| Audio FX edit | Prior Replace/Presets/power/Confirm/Discard and 3 slots | Editors/AudioEffectParameters and preset tests | Bypass editing, every parameter, replacement/snapshot semantics, preview rollback | DOCUMENTED reference; #11 |
| Shimmer/verbs | Prior control names/values; UI observation only | Independent C engines; spectral/stability/sanitizer checks | No matched-path perceptual or null-equivalence evidence | DOCUMENTED UI; audio UNKNOWN; #9/#10 |
| Delay/processor translation | MainStage Tape Delay source-backed serialized control record in MAINSTAGE-TAPE-DELAY | Processing parser and 3-rate impulse/automation tests | Clean static subset only; color/freeze/modulation rejected | DOCUMENTED reference fields; VERIFIED synthetic; #10/#6 |
| MIDI FX | Prior four types; manual mapping constraints in #11 | MIDIFXProcessor + Editors; deterministic scheduler tests | Timing 5 ms main timer; maximum mapping/learn/range contract needs focused review | DOCUMENTED; #11/#15/#111 |
| Snapshot capture | [First-party manual](https://support.sundaysounds.com/article/3139-patch-snapshots) specifies sound levels, effect bypass and wheel; parameters patch-wide | Models SnapshotSoundState and Store.recall also save pan, programs, full effects/AU/rack/tonic | Confirm intentional extended StageKeys semantics or plan lossless legacy migration; do not erase existing states | DOCUMENTED manual / VERIFIED code; #16 decision D01 |
| Snapshot slots/notes/transitions | Prior five positions/notes; manual rename/reorder/clear | SnapshotSlot/SnapshotMorph/Store tests; UI contexts | Selected empty behavior, transition UI, accessibility and live rapid recall | DOCUMENTED; #16/#19 |
| Tonic | Power/key/volume visible; settings blocked in 30 Oct Demo | Transactional eligible sampler picker; AU rejected with explanation | Restricted reference sound selection UNKNOWN; validate StageKeys independently | DOCUMENTED partial; #16; #54 software closed |
| MIDI devices/Learn | Prior Primary/Secondary/velocity/monitor and learn overlay; Settings manual | CoreMIDI ownership/filtering/learn code; virtual tests | Both controllers currently dispatch notes/CCs through one OR guard; Primary-only note requirement is unmet in source. Tonic/effect Learn targets absent; physical boot still needs capture | DOCUMENTED; #15/#88 |
| Transpose/tempo | Additional Controls manual; no current runtime capture | PatchTransposition/Models/Store; PR #125 | Timing remains block/timer based; supported export/legacy/live pathways | DOCUMENTED; #111 |
| Flex Routing | 30 Oct per-device categories and sound overrides; Settings manual | Explicit not-implemented message and stereo graph | Device pair enumeration and per-sound graph absent | DOCUMENTED reference / VERIFIED absence in graph; #107 |
| Metronome | 30 Oct/manual sound/accent/master-follow controls | Independent click/accent engine and persisted settings | Long clock/routing/combined headroom; 4/4 toolbar text | DOCUMENTED reference / VERIFIED source; #3/#108 closed |
| Preload/keyboard/meters | 30 Oct Performance settings | Some layer range/disable-silenced controls; global output meter | Preload window, per-sound meters and separate display/play modes missing | DOCUMENTED; #109 |
| Background/interruption | Settings/optimization manual documents mobile option | iOS non-active phase Panic and interruption stop; background entitlement alone insufficient | Policy/state recovery missing | DOCUMENTED manual / VERIFIED source; #113 |
| Setlists/patch exports | Manual portable independent instances/templates | Local duplicate/Trash/file document path; personal packs carry sounds only | Templates/portable dependency/identity package larger than existing file export | DOCUMENTED; #114 product scope |
| MainStage/EXS conversion | Reference import equivalence not presumed; MainStage source documents distinct from Sunday app | Explicit supported subset in MAINSTAGE-COMPATIBILITY-MATRIX | Unsupported engines/modern modes/source topology remain archived or rejected | VERIFIED source; #5/#6/#7 |
| Audio Units | Reference custom/generic hosting not observed in deep audit | Native hosting/editor lifecycle tests and platform policy | Cannot infer identical plugin architecture; real AU matrix needed | UNKNOWN reference; independent #12/#13/#14/#53 |
| Errors/recovery | Reference error behavior unexamined | Startup states/retries; graph changes can fail without general rollback | Inject failures then physical reproduction; no reference claim needed | UNKNOWN reference; VERIFIED source; #110/#123 |
| Cloud/Prime/downloads/account | Prior visible backup controls and Demo warnings; no backup/download execution | No CloudKit implementation; local personal content only | #121 independent proposal conflicts with historical exclusion; Prime remains outside scope | DOCUMENTED/UNKNOWN; decision D02 |

Manual sources are first-party product documentation, not observed behavior of the installed 2.5.2 Mac build. Relevant pages: [Settings](https://support.sundaysounds.com/article/3194-settings), [Sounds](https://support.sundaysounds.com/article/3141-sounds). No vendor screenshots/art/audio are copied into the repository.

## Bounded reference continuation sessions

| Session | Preconditions | Reproducible sequence | Record / stop condition |
| --- | --- | --- | --- |
| R01 snapshots | Disposable authorized patch; visible license state; preserve original | Capture one slot; change a parameter/bypass/fader/wheel; recall; reopen | Before/after values and persistence; discard scratch; verify exact manual scope |
| R02 MIDI learn | Authorized keyboard and harmless CCs | Primary/Secondary note/control/filter tests; conflict/unlearn/reset; restart | MIDI monitor source/channel/event and resulting state; no global reset on user data |
| R03 sound/effect transactions | Disposable patch and authorized sound | Preview, bypass, preset, replace; cancel then confirm separately | Values before/during/after, save/reload and snapshot interactions; audio if authorized |
| R04 routing/performance | Record device; avoid changing live system setup without need | Inspect available categories/overrides/preload/keyboard/meter options | Visible controls plus restrictions only; do not claim audio routing from labels |
| R05 matched DSP | Same authorized dry source/MIDI/tempo/rate/block/gain/route | Isolate one processor/control and capture both paths | Source hashes, wet/dry/bypass, alignment, error metrics/listening, exceptions |
| R06 mobile | Physical supported iPad/iPhone, authorized AUv3 | Foreground/background, lock, interruption, reopen editor, route change | Model/OS/thermal/memory/latency; defer under #105 until owner resumes hardware work |

For each session record date/time/timezone, app/build/hash, license access, platform, starting state, exact actions, screenshot IDs where available, state mutation, persistence result, interactions, edge cases and uncertainty. Audio additionally requires fixture provenance, note/velocity/pedal sequence, sample rate/block size/device, tempo, gain staging and capture location. If blocked, retain UNKNOWN and the exact next action; never work around entitlements.
