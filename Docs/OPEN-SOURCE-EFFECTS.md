# Open-source effects integration plan

## Goal

StageKeys should offer a complete, high-quality live effects collection without
depending on proprietary DSP or copying another product's implementation. Open
source is an engineering input, not an automatic quality signal: a candidate is
adopted only when it improves sound or maintainability and still meets the
real-time, compatibility, licensing, and performance requirements below.

StageKeys keeps one native C render architecture. Adapted DSP runs inside the
existing engine and must not introduce a second plugin framework, allocate on
the render thread, perform file I/O, take locks, or require network access.

## Current effect inventory

Effect IDs are part of the patch format and must remain stable.

| ID | User-facing effect | Current implementation | Open-source direction |
|---:|---|---|---|
| 1 | Tone | Native filter | Retain and strengthen reference tests |
| 2 | Tremolo | Native amplitude modulation | Retain; consider additional wave shapes independently |
| 3 | Delay | Versioned legacy-linear and Stage Delay cubic cores | `stage-delay-v1` adapts Signalsmith interpolation |
| 4 | Bitcrusher | Native quantizer/sample-rate reduction | Retain; add antialias and transition tests |
| 5 | Chorus | Versioned legacy and Stage Chorus cores | `stage-chorus-v1` adapts DaisySP foundations |
| 6 | Compressor | Native feed-forward compressor | Retain; improve metering and program-dependent modes independently |
| 7 | Equalizer | Native eight-band parametric EQ | Retain |
| 8 | Flanger | Versioned legacy and Stage Flanger through-zero cores | `stage-flanger-v1` reuses the qualified Stage Delay cubic tap and Stage Chorus modulation work |
| 9 | Gain | Native | Retain |
| 10 | Halo Shimmer | Native pitch-shifted feedback reverb | Evaluate pitch cores separately from the reverb network |
| 11 | Overdrive | Versioned legacy and Stage Overdrive cores | `stage-overdrive-v1` is independent ADAA tanh saturation; a documented Airwindows comparison remains pending |
| 12 | Pitch Shifter | Native | Research Signalsmith Stretch subject to latency limits |
| 13 | Stage Reverb | Versioned reverb family | Room, Hall and Ambient profiles active |
| 14 | Rotor | Native Doppler/amplitude model | Audit permissive rotary candidates; retain if none clearly wins |
| 15 | SolaVerb | Native ambient/modulated reverb | Improve independently; share only proven primitives |
| 16 | Silver Reverb | Native acoustic reverb | Improve independently; share only proven primitives |
| 17 | Clip Distortion | Versioned legacy and Stage Clip cores | `stage-clip-v1` smooths the existing independent ADAA clipper; oversampling and Airwindows comparison remain pending |

An empty effect slot remains ID 0. Adding an effect requires a new ID; an
existing ID must never be repurposed for a different effect.

## Approved and candidate upstream projects

| Project | License | Suitable use | Decision |
|---|---|---|---|
| [DaisySP](https://github.com/electro-smith/DaisySP) | MIT | Small delay-modulation building blocks | Approved for isolated, attributed adaptations. Stage Chorus is the first integration. |
| [Signalsmith DSP](https://github.com/Signalsmith-Audio/dsp) | MIT | Fractional delay, interpolation and pitch/time processing | Approved for prototypes. Each adopted file still needs pinned provenance and a bundled notice. |
| [Airwindows](https://github.com/airwindows/airwindows) | MIT | Saturation, clipping, ambience and character processors | Candidate-by-candidate listening and CPU shootout; do not import the entire catalog. |
| [ChowMatrix](https://github.com/Chowdhury-DSP/ChowMatrix) | BSD-3-Clause, with separately licensed dependencies | Matrix-delay design reference | Do not vendor wholesale. It is tightly coupled to JUCE and supporting modules. A framework-independent adaptation requires a file-level audit. |

Do not add GPL, AGPL, non-commercial, source-available, or ambiguous-license
code to the shipping application. A permissive top-level repository license is
not enough when copied files, submodules, generated tables, models, presets, or
impulse responses have different terms.

## Provenance and license checklist

Every adapted processor must land with all of the following in the same pull
request:

1. Upstream repository URL and exact reviewed commit SHA.
2. Names of the source files and algorithms that informed the adaptation.
3. A complete license notice under `Licenses/`.
4. A short description distinguishing copied, adapted, and independently
   written portions.
5. Confirmation that no presets, impulse responses, branding, or UI assets were
   imported unless their licenses explicitly permit redistribution.
6. A dependency review showing that the render path remains framework-free.

Stage Chorus provenance is recorded in `Licenses/DaisySP-MIT.txt`; Stage Delay
provenance is recorded in `Licenses/Signalsmith-DSP-MIT.txt`. StageKeys'
independent reverb implementation is covered by
`Licenses/StageKeys-Dense-Reverb-MIT.txt`. Stage Flanger adds no new upstream
code: it is an independent through-zero modulated-delay implementation that
reuses the already-noticed Signalsmith cubic interpolator. Its design and
verification are recorded in [STAGE-FLANGER.md](STAGE-FLANGER.md).

## Real-time integration contract

All processors must:

- use memory allocated during engine creation or configuration, never during
  rendering;
- avoid locks, Objective-C/Swift calls, logging, exceptions, and unbounded
  loops in the audio callback;
- handle mono and stereo without collapsing stereo width or changing dry gain;
- produce finite, bounded samples for every valid parameter combination;
- smooth audible gain, time, feedback, filter, rate, and mix changes;
- clear all delay, filter, oscillator, and envelope state on Panic;
- tolerate sample-rate and buffer-size changes;
- preserve tails during ordinary patch transitions where the architecture
  supports it, while still offering a deterministic hard reset;
- remain stable when multiple instances are stacked.

Shared primitives should be introduced only after one effect proves them. For
example, a fractional-delay implementation should first qualify in Stage Delay,
then be reused by Chorus, Flanger, Rotor, and reverbs without duplicating subtly
different interpolation code.

## Preset compatibility and versioning

Existing patches must continue to sound as authored. New DSP therefore uses an
explicit core identifier stored in the effect model, such as
`stage-chorus-v1`. A missing identifier selects the legacy processor.

- Never silently migrate an existing patch to a new core.
- New effect instances may use the current stable core by default.
- The editor must identify the active core and offer an explicit upgrade.
- Saving, loading, snapshots, undo, duplication, and MainStage conversion must
  preserve the core identifier.
- Core-specific hidden render parameters are appended after visible controls;
  they must not alter the public control indices.
- Removing a legacy core requires a separate patch-format migration and cannot
  happen while supported user documents still reference it.

## Acceptance gates

### Automated correctness

Each processor needs sanitizer-backed coverage at 44.1, 48, and 96 kHz for:

- finite and bounded output;
- dry identity at zero mix or bypass;
- meaningful wet output and stereo behavior;
- parameter limits and rapid automation;
- Panic silence and repeatable reset;
- preset encode/decode round trips;
- block-size invariance within the algorithm's documented tolerance;
- stacked instances and at least ten seconds of sustained processing.

Delay-based effects additionally test interpolation continuity and feedback
stability. Dynamics test static transfer, attack, release, makeup, blend, and
bypass. Pitch effects test tuning, alias rejection, latency, and chordal input.
Reverbs test predelay, early/late energy, decay ordering, tail continuity, and
feedback safety.

### Listening qualification

Automated tests cannot establish musical quality. Compare candidates at matched
integrated loudness and identical dry/wet ratios using:

- transient piano at soft, medium, and hard velocities;
- sustained organ;
- bright polyphonic synth;
- wide stereo pad;
- mono source routed through a stereo instance;
- fast patch changes and snapshot morphs.

The panel should listen blind for metallic ringing, modulation pitch wobble,
image instability, transient smearing, grain, pumping, noise buildup, and tail
cutoffs. Retain the existing engine unless the candidate is a repeatable win.

### Performance qualification

Measure release builds, not sanitizer builds. Record median and worst render
time, CPU percentage, persistent memory per instance, reported latency, and
dropouts for one, three, and eight instances. Test the smallest supported live
buffer at 44.1 and 48 kHz and a stress configuration at 96 kHz. A Mac benchmark
does not replace physical iPad testing.

## Implementation order

### Phase 1 — modulation and delay foundation

1. **Stage Chorus:** complete. New instances use `stage-chorus-v1`; the legacy
   core remains available.
2. **Stage Delay:** complete for native delays. New instances use
   `stage-delay-v1` cubic interpolation while existing and imported delays keep
   their authored behavior, including sync, independent left/right time,
   ping-pong, filtering, and MainStage-imported dry/wet routing.
3. **Stage Flanger:** implemented with `stage-flanger-v1`. New instances select
   it; existing patches keep the legacy core until the editor's explicit upgrade.
   The Stage core uses a fixed 1.5 ms reference path, a bipolar cubic sweep that
   crosses zero, 90° stereo modulation phase, signed soft-limited feedback and
   20 ms control smoothing. Mix 0 is an exact dry bypass; engaged Mix adds the
   1.5 ms reference latency. Local sanitizer checks pass at 44.1/48/96 kHz;
   Apple CI, listening and release-build CPU/iPad qualification remain pending.
   See [STAGE-FLANGER.md](STAGE-FLANGER.md).

Exit gate: no zippering during time changes, no runaway feedback, stable stereo
operation, and a measured CPU/memory budget suitable for eight live instances.

### Phase 2 — nonlinear effects

1. **Stage Overdrive:** candidate `stage-overdrive-v1` is implemented as an
   independent ADAA tanh core with smoothed controls and legacy retention. The
   documented Airwindows shootout and blind listening remain pending before it
   is described as an improvement.
2. **Stage Clip Distortion:** candidate `stage-clip-v1` is implemented for the
   imported ClipDist path. It retains the existing ADAA curve and smooths all
   audible controls, including filter and shelf coefficients. Blind listening,
   oversampled-reference alias measurement, and Airwindows comparison remain
   pending; no oversampling is added.
3. Keep input, output, mix, tone, and bypass gain conventions consistent across
   all distortion types. Stage Overdrive preserves the legacy drive and boost
   conventions and documents its exact-dry condition.

Exit gate: level-matched musical improvement on piano, organ and synth with no
unbounded output or discontinuity during automation.

### Phase 3 — pitch and ambient effects

1. Benchmark the existing pitch shifter against a render-safe Signalsmith
   prototype, including reported latency and chord tracking.
2. Improve Halo Shimmer by separating pitch quality from diffusion, feedback,
   damping and stereo spread.
3. Reuse a new pitch core in SolaVerb only after it passes live-latency and
   allocation requirements.

Exit gate: tuning remains within the defined tolerance, chord changes do not
produce clicks or stuck grains, and latency remains acceptable for live keys.

### Phase 4 — space and motion

1. Finish blind qualification for Stage Reverb Room, Hall and Ambient.
2. Evaluate a small set of Airwindows ambience/reverb candidates as references,
   not as an automatic replacement.
3. Audit Rotor against permissively licensed rotary implementations and improve
   the native model if a clean dependency-free candidate is unavailable.

Exit gate: convincing acoustic and ambient spaces, natural tail transitions,
stable feedback, preserved stereo width, and acceptable stacked-instance CPU.

### Phase 5 — utility polish

Finish metering, parameter units, accessibility, preset naming, automation
smoothing, and consistent editor layouts for Tone, Tremolo, Bitcrusher,
Compressor, Equalizer, and Gain. These effects do not need third-party DSP to
benefit from stronger testing and UI consistency.

## Per-effect pull-request template

Every effect pull request should answer:

- Which existing user problem does this solve?
- What upstream code or research informed it, at which revision and license?
- Is the implementation copied, adapted, or independent?
- What is the stable core identifier and legacy behavior?
- Which controls map to which DSP parameters and units?
- What are the worst-case feedback and gain bounds?
- Does it allocate, lock, log, or call platform APIs while rendering?
- Which automated, listening, CPU, memory, and device results passed?
- What remains unverified, especially on physical iPad hardware?

No processor should be described as sonically identical to another product.
The release claim should be narrower and testable: StageKeys provides its own
permissively licensed or independently developed effects that meet the stated
quality, compatibility, and live-performance gates.
