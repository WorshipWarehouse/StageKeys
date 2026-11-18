# Mac acceptance for Sunday, 22 November 2026

Started 18 November at `f25dcc15b4b22d98dfa26e23aa1c7e2026f4c79d`.
This record tracks work, not a readiness claim. Physical iPad/iPhone work stays deferred.

## Target and available evidence

The owner will use a MacBook, a KeyLab controller and a different audio interface.
The owner clarified the target as multiple M1-or-newer Macs with different standard MIDI controllers/audio interfaces, rather than qualification of one fixed rig. Required content includes Grand Beyond Measure and the Danny Lopez Signature Sound Bank. Broader model/interface/controller results remain unverified until exercised. Current development hardware is an M4 Mac mini,
16 GB RAM, AudioBox USB 96 at 48 kHz. Owner authorized audible testing and can help
with reconnects. Development-rig results cannot qualify the different Sunday rig.
Private source sounds, sessions, AU state and recordings remain outside Git.

## Ordered work and boundaries

1. Finish #214 preview disclosure and failure/cancellation coverage; privately
   exercise both authorized pianos through the actual Mac import UI.
2. Exercise startup and live edit recovery (#110/#123), preserving operation,
   route, revision and active note/session state; retain genuine failures if
   reproduced. Injected failures do not stand in for a real reproduction.
3. Exercise clean-profile setlist/library restore and visible workflows
   (#20/#114/#16/#17), including older/corrupt data and independent copies.
4. Inventory the owner's exact MainStage patches and Nord artist files. Existing
   `.npno` attack-only support does not establish `.nsmp*`/program/synth/effect
   support; unsupported dependencies need explicit implementation/capture or
   rejection, not a fallback sound.
5. Qualify actual plugins, controllers, patch transitions and bounded resources;
   define the workload/limits before running the sustained #4 soak. Measure
   render deadlines/underruns and resource growth, not just average CPU.
6. Repeat the live scenarios on representative M1-or-newer Mac/interface/controller combinations, with owner listening and a full-set rehearsal. One development machine does not establish all combinations.

The software work uses an isolated `codex/mac-sunday-acceptance-20261118`
worktree. It preserves the three preexisting untracked drafts in the main checkout.
No public signing, notarization, installation, cloud upload or distribution is
inferred from this acceptance work. Prepare those artifacts/commands separately
if needed, and obtain explicit owner authorization for those actions.

## First bounded implementation

`NordNative.Preview` supplies source revision, decoded/storage cost and explicit
Mac versus deferred-device eligibility. `SoundImportView` displays them before
conversion. A DEBUG-only precommit seam supports deterministic cancellation and
storage failure without filling a real disk. Generated Store tests must preserve
catalog/session/source bytes, live note/sustain/audio state and unrelated assets
on failure, including a real catalog-rotation filesystem failure and concurrent
edits. Existing native import/pack relocation checks remain required. The source
schema, decoder and sample payloads are unchanged.

Results and closures are added only after their actual checks pass and reviewed
implementation is published. A clean build alone does not make Sunday ready.

## Results so far

- Generated Nord transaction/import/pack gate: 4 passed, 0 skipped, 0 failed.
  Includes simulated storage failure at commit boundary, real failed catalog
  previous-copy write, concurrent edit, cancellation after preparation, invalid
  residual codec, truncated source, Discard and successful retry. Existing
  catalog/session/source bytes, playing unit and held note/sustain are preserved.
- Existing isolated master-muted live probe: 96 production sampler patch
  changes, 94 verified stopped releases, 15.69 seconds on the development route.
  This is output-progress/disposal evidence, not listening/latency/soak evidence.
- Selected Danny Lopez bundle: 708,172,466 bytes; 9 piano files, 3 sample
  instruments, 32 programs plus dependency manifest. SHA256
  `6203b01e965d4ad986cfb130112eed286ddf5eadffd731af2977055c436ff624`.
  The full artist programs are not established by importing their piano files.
- Grand Beyond Measure exact source tree
  `017184130074ac824125ba43437d84f9dc9879a8`: seven channels, five EXS
  dependencies and two ES2 channels. The two ES2 engines and untranslated
  source routing/effects/MIDI cannot silently disappear. Private metadata and
  complete parser reports are outside the checkout.
