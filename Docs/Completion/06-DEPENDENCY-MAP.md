# Dependency map

Edges express proposed engineering prerequisites, not GitHub dependency mutations. Existing release umbrellas remain open. Conditional nodes are scope choices; the roadmap task table is the full acceptance/validation source.

```mermaid
flowchart TD
  T00[00 Baseline and scope] --> T01[01 Product and license decisions]
  T00 --> T02[02 Startup hardware reproduction]
  T00 --> T03[03 Live graph fault reproduction]
  T03 --> T04[04 Atomic live graph changes]
  T04 --> T05[05 Plugin containment and editors]
  T00 --> T06[06 Bounded audio-check callback]
  T00 --> T07[07 All-branch output headroom]
  T01 --> T08[08 Migration and recovery contract]
  T08 --> T09[09 Supported import corpus]
  T09 --> T10[10 Source topology and sound order]
  T04 --> T10
  T10 --> T11[11 Optional multi-output]
  T04 --> T11
  T05 --> T12[12 Hardware MIDI streaming latency]
  T02 --> T12
  T07 --> T12
  T04 --> T12
  T01 --> T13[13 Performance and accessible UI]
  T05 --> T13
  T10 --> T14[14 Tempo scheduling qualification]
  T04 --> T14
  T04 --> T15[15 Optional bounded preload]
  T05 --> T15
  T08 --> T15
  T11 -. if routing included .-> T15
  T10 --> T16[16 DSP and gain qualification]
  T14 --> T16
  T10 --> T17[17 Optional batch import]
  T17 --> T18[18 Optional checkpoint resume]
  T08 --> T18
  T04 --> T19[19 Mobile lifecycle]
  T08 --> T19
  T19 --> T20[20 Physical mobile owner-resumed]
  T05 --> T20
  T13 --> T20
  T06 --> T21[21 Soak and rehearsal beta]
  T07 --> T21
  T08 --> T21
  T12 --> T21
  T13 --> T21
  T14 --> T21
  T16 --> T21
  T15 -. if included .-> T21
  T20 -. mobile only .-> T21
  T21 --> T22[22 Release qualification]
  T01 --> T22
  T08 --> T23[23 Optional setlist packages]
  T13 --> T23
  T22 --> T24[24 Optional cloud AI and meter]
  T23 -. cloud backup schema .-> T24
```

## Cross-cutting constraints

- #123 graph transactions precede new graph features #107/#109. A safe tail pool (#55) is compatible work but not a substitute for rollback.
- #20 serialization/recovery precedes new backup/checkpoint/share formats. A local atomic file write is not atomicity across every state file or a cloud restore.
- #6 source topology precedes faithful multi-instrument decomposition and DSP path comparisons. Match processor order and gain before interpreting a null/residual measurement.
- #16 snapshot contract precedes data migration or edits that assume only bypass/levels. Preserve existing full captured state until an approved versioned decision exists.
- #13 plugin containment and real state/editor matrix precede preload of arbitrary third-party components. A main-queue timeout cannot contain a blocked main queue.
- #105 is deferred by owner request. No task here resumes it automatically. A Mac-only release can qualify separately; public mobile qualification still needs actual physical evidence.
- #64 is an owner decision, not a dependency on choosing any particular license. Public distribution needs an explicit record and component/provenance review, not a guessed MIT label.

## Safe parallelization boundaries

| Workstream | Can overlap | Shared-state constraint |
| --- | --- | --- |
| Graph failure diagnosis/rollback | Recorder and persistence analysis | One owner for ExternalInstruments/AudioController/Store graph paths |
| Recorder callback transport | Graph diagnosis | Isolate AudioDiagnosticRecorder changes; coordinate tap interface with graph owner |
| Persistence/migrations | DSP measurement and UI observation | One owner for Models/SessionSettings/Store persistence fields |
| Reference UI observation | All implementation analysis | Read-only/disposable state; retain license and action logs |
| DSP render measurement | UI/accessibility evidence | Freeze source/processor/gain identities; no overlapping unreviewed DSP mutations |
| Device measurements/soak | Documentation and provenance | Frozen tested binary, owned rigs and settings; invalidate evidence when audio inputs change |

These are opportunities for future explicitly approved delegation. This audit did not run parallel model agents. Tests/builds were independent processes against unchanged sources.
