# Sunday Keys 2.5.2 deep UI audit

Observed 2026-10-13 in the signed-in Mac app, Demo Mode. This supplements UI-WALKTHROUGH.md. Effect selections were staged to inspect editors; no Confirm was used and each editor session ended with Discard Changes. Account, downloads, purchases, backups and library data were not changed. Values below are observed initial editor values, not guarantees of factory defaults for every patch.

## Layout findings

At the observed 1194 × 866 window, title bar is 30 px; toolbar occupies y=38–82. Left sidebar x=8–307 (299 px), rack x=318–1186. Five visible channel strips are about 168 px wide with 8 px gaps. Rack scrolls horizontally to 15 modules. Color order for populated demo channels: amber, green, blue, purple, pink. Channel name and separate edit icon occupy top 52 px. Real faders have shaded rectangular caps, central color line, lateral ticks, numeric dB label and infinity mark. Notes and Effects are a segmented switch, not independent page buttons.

Notes mode removes effect slots and shortens faders: channel region y=100–464; note panel x=315,y=484,w=872,h=135. Snapshot row y=635–683. Keyboard/layer summary y=700–852. Sidebar setlist y=96–386; tonic pad y=395–683, with separate vertical fader. Notes empty state is a large plus, 'Add Snapshot Note', and explanatory line. Note editor centered x≈270,y≈178,w≈656,h≈303; header has left/center/right alignment buttons, title, five-line limit and close. Text area is 150 px tall; Discard Changes and initially disabled Confirm in footer.

Layer editing is a full overlay below the toolbar, not a small popover. It replaces rack/sidebar with reverse-order rows 15→1, colored left accents, reorder handles, dashed empty rows and horizontal colored ranges with circular endpoint handles. Bottom piano remains. Visible populated labels: Sub Bass A-1–E2, Felt Piano A-1–C7, Trance Lead G2–C6, Simple Worship Arp C1–E5, DX E Piano A-1–C7. Empty rows are named 'Empty Sound Module N'. Help at upper left; sustain/layer/keyboard mode cluster upper right. Keyboard mode disabled in this view in Demo. No endpoint drags were performed.

## Per-channel effect contract

Each populated channel exposes one MIDI effect and three separately numbered Audio 01/02/03 slots, each with own power button. Editor top contains Replace Effect, Presets and Effect ON toggle. Footer Discard Changes/Confirm. Replacement catalog explicitly warns: confirming changes updates existing Patch Snapshots. StageKeys should model editing as a draft transaction and implement this persistence behavior deliberately.

### Audio catalog (15)

| Effect | Observed controls / values |
|---|---|
| Bitcrusher | Bit depth 10; sample rate 5 kHz; mix 100% |
| Chorus | Frequency .68 Hz (0–20), depth 40% (0–100), feedback 20% (0–100); output boost 1 dB, mix 100% |
| Compressor | Input gain 0 dB; envelope attack 20 ms/release 60 ms; ratio 2:1; threshold -40 dB; dry/wet 0%; output gain 0 dB |
| Delay | Feedback 30%; subdivision quarter/dotted eighth/eighth/sixteenth/32nd icon buttons; ping-pong on; filter 1000 Hz; mix 50% |
| Equalizer | Eight bands shown: high pass 20 Hz, low shelf 70 Hz, peaks 100/250/1000/2500 Hz, high shelf 7500 Hz, low pass 20000 Hz. Gains 0 dB; four peak bandwidths .5. AX traversal order interleaves labels, so verify exact column ordering visually before matching |
| Flanger | Rate .2 Hz (.1–10); depth 50%; feedback .8 (-.95–.95); mix 50% |
| Gain | Gain 0 dB, range -infinity to +6 dB |
| Halo Shimmer | Shimmer amount 75%, feedback 66%, size 90%, diffusion 75%; character modulation 50%, quality 100%, low cut 100 Hz, tone 66%; dry 100%, wet 20% (AX label/value ordering needs visual confirmation) |
| Overdrive | Drive 96%; low cut 402 Hz (20–800), tone 4877 Hz (600–20000); mix 40%; boost 2 dB |
| Pitch Shifter | Pitch +12 semitones (-24–24); amount 20% |
| PrimaVerb | Reverb-size stepper Medium Hall; predelay 0%; reflectivity 30%; low cut 100 Hz; tone 20000 Hz; quality 100%; chorus amount 0%; rate 1 Hz; dry 80%, wet 40% |
| Rotor | Slow/Brake/Fast; mic balance Both, distance 18 cm, spread 130 cm; ambience size 90%, width 82%, amount 35%; mic model Dynamic; cabinet Classic; front/back mic position; slow rate 44 rpm, fast 402 rpm, acceleration 2.5; drive 0%; output 0 dB |
| SolaVerb | Predelay 20 ms, size 50%, reflectivity 50%; quality 100%; low cut 100 Hz; tone 70%; pitch mod 33%, chorus amount 20%, rate 1 Hz; dry 80%, wet 40% |
| Tone | Frequency 20000 Hz (20–20000) |
| Tremolo | Depth 80%; stereo off; frequency Temp/Hz switch; subdivision 1/8 |

Many parameters are custom-drawn and exposed as combined AX text rather than native sliders. A visually similar UI alone does not prove DSP parity. Preset submenus and every parameter range were not exhaustively exercised.

### MIDI catalog (4)

| Effect | Observed controls |
|---|---|
| Arpeggiator | Subdivision 1/8; styles Up/Down/Up-Down/Down-Up/Random/Chord; Steps minus/16/plus; velocity grid with +/- and reorder controls; horizontally scrolling step editor; numbered note grid 1–128; Help |
| Easy Chord | Input→Output mappings; numbered first row; delete mapping; Add Chord; Help; note grid custom drawn |
| Octave Up | Blend 100% (0–100); explanatory text says additional octave note velocity is controlled by Blend |
| Sequencer | Subdivision 1/8, velocity 100%; Steps minus/16/plus; Input→Output mapping rows; horizontally scrolling step list; delete mapping; Add Sequence; numbered note grid 1–128; Help |

## Additional pages and restrictions

- Menu identifies V 2.5.2; MIDI Learn, Settings, Help and Support, Cloud Backups, Sound Downloads Manager, View User Account and Sign out. Basic Settings and sound-channel pages are covered in prior audit.
- Sound Downloads Manager: centered ~800 × 568 modal, title 'Available Content from your Account'; explanatory account-content/download text; initial skeleton loading rows resolve to installed 'Demo Sounds 1.1.6 607 MB' with check icon. No download or removal invoked.
- Cloud Backups opens despite a Demo warning: explanatory library backup copy; 0/0 stored; New Backup; automatic-on-open toggle off; frequency 'Weekly on Wednesdays'; 'Only show Backups from this Device' checkbox; Restore Backup. No backup actions invoked. These controls' availability must not be represented as successfully tested backup capability.
- Prime toolbar icon click presents 'Not available in Demo mode' and no integration editor. Prime workflow blocked by license/demo state.
- Help and Support click caused no in-app page change (likely external destination); external help was not audited here. View User Account/sign-out were intentionally not invoked.

## Implementation acceptance matrix

| Surface | Observed | Needed in StageKeys |
|---|---|---|
| Main Effects/Notes rack | Yes | Accurate dimensions, segmented switch, real strip heights, scroll clipping, dB cap/ticks |
| All 15 module slots | Yes | Independently persistent channel state, numbered 3-FX chain + MIDI slot |
| FX edit lifecycle | Yes | Draft edits, cancel restores all state, confirm updates snapshots consistently |
| Audio DSP parity | UI only | Implement each algorithm and meaningful parameter response, offline signal tests |
| MIDI transformation parity | UI only | Chord/sequence/arp/octave semantics with note-off, sustain, stop/panic correctness |
| Layer editing | Read-only inspected | Endpoint dragging, range bounds, reorder, keyboard alignment; no false demo restriction |
| Notes | Editor inspected | Five-line validation, alignment, snapshot-linked persistence |
| Downloads | Installed demo metadata | Local import/source library workflow; independent content assets |
| Cloud/Prime | Demo restricted | Mark unverified; avoid inventing parity |
| Presets/plugin/native external editors | Not covered here | Separate audit/test; do not claim 1:1 |

## Follow-up MIDI source inspection

Settings → Midi has two numbered rows: Primary MIDI Controller (Channel 01, All devices) and Secondary MIDI Controller (Channel 01, None). Opening Primary source choices showed All devices, None, live AudioBox USB 96, live StageKeys to External App, plus remembered OB-Xd Virtual MIDI Out and old StageKeys virtual endpoints marked Not Connected. There is no visible auto-connect switch. No selections changed. Keyboard Velocity Scaling is a dual-endpoint range control, 0–127. Bluetooth/Network MIDI section says connect devices then assign as Primary/Secondary, with Open Audio MIDI Setup button. MIDI Monitor presents Device, Message, Channel, Value columns and an expand arrow.
