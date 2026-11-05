# Portable setlist sharing

A saved setlist or the current document can be exported as a `.stagekeyssetlist` package and imported on another StageKeys installation without a hosted service. The package is a versioned StageKeys-owned JSON document; the file extension and `studio.stagekeys.setlist-share` uniform type are registered on both app targets.

## What travels

The package carries the setlist graph and authored metadata: patches, layers and ranges, gains, pan, effects, MIDI programs, snapshots and notes, tempo/transposition, Tonic Pad state, and sampler/Audio Unit/MIDI source references.

Dependency records list the names and stable identifiers needed by the destination. They are references, not payloads. The package never contains:

- sample audio or sampler instrument payloads;
- Audio Unit binaries;
- saved Audio Unit document state (`pluginState`);
- source archives;
- local absolute source paths in user-visible notes.

Exported notes replace a local path such as `/Users/…` or `/Volumes/…` with `[source location]`. The redaction consumes the rest of that line (stopping only at a line break, comma or semicolon), so a path containing spaces cannot leave a home-directory or filename fragment behind. It also recognises `/home`, `/Applications`, `/System`, `/opt` and `/private`. Over-redacting trailing prose is intentional for this privacy boundary. A saved Audio Unit's local availability, vendor/version display fields and custom-view flags are also omitted; the component triple and display name remain. On import the destination uses its own plug-in state, not the sender's.

## Package envelope

```json
{
  "format": "stagekeys-setlist-share",
  "version": 1,
  "exportedAt": 0,
  "checksum": "<sha256 over canonical content>",
  "content": {
    "setlist": { "version": 4, "patches": [] },
    "dependencies": [
      { "kind": "audioUnit", "name": "…", "identifier": "…", "detail": "…" }
    ],
    "warnings": ["…"]
  }
}
```

`checksum` is SHA-256 over the canonical (sorted-key) JSON encoding of `content`. It detects accidental corruption; it is not a signature, so a deliberately rewritten package can be resealed. Schema and payload validation still run on every import. Files are bounded to 8 MB. The reader also requires a sorted, unique dependency list that exactly matches the references (including their names and details) derived from the setlist, so a package cannot hide or mislabel a dependency by editing the list. Packages containing saved plug-in state are refused.

## Import planning

Reading a package only computes a plan; nothing is written and the current performance keeps playing. The plan shows:

- unavailable Audio Units, missing sampler presets/samples and unreadable references checked against this device;
- device-specific external MIDI destinations, which must be reselected;
- identity collisions with existing saved setlists, and the replacement identities that will be assigned;
- the destination name, with a ` Copy` suffix when the name is already present.

Authored patch, layer and snapshot identities are preserved when they do not conflict, so repeated copies stay independently addressable. If an identity already exists in the local library, only the conflicting instance gets a fresh UUID; references between the document's parts remain intact. An older schema version (1–3) is upgraded to version 4 in the destination copy only.

The user then chooses:

- **Save and Load** — runs the existing live admission check for the first patch, preserves the current saved setlist, saves an independent library copy, then activates it. It is disabled when a known dependency is missing, when patches are locked, or when saved session/settings recovery is required; the sheet explains that recovery must happen in Settings first.
- **Save to Library** — saves an independent copy without activating it, restarting audio or changing the current performance. Missing dependencies do not block this path.

## Independent patch exports

Saving a patch to the library is a local action, not a share. **Save Patch to Library** in the patch menu writes the active patch as its own one-patch library document:

- the copy gets fresh patch, layer and snapshot identities, so later edits to the source setlist can neither change it nor collide with it when it is added back;
- authored patch settings (name, tempo, transposition, layers and ranges, snapshots, Tonic Pad state, Program Change opt-in) are preserved, and references between the exported parts still point inside the export;
- setlist-level MIDI CC assignments are deliberately not copied, because they belong to the source document rather than to the patch;
- the current setlist is not saved, activated or restarted, and audio keeps playing;
- exporting the same patch again adds another document. Overwriting a library entry stays an explicit library action; an export never reuses an existing identity.

An exported patch is an ordinary one-patch library document, so it also appears in the patch picker that adds a saved patch to the current setlist. A local library export is not a share: plug-in state and local source references stay in the copy instead of being stripped, and missing sampler or Audio Unit content is not detected at export time. The existing runtime admission and failure handling still apply when the exported patch is loaded.

## Offline links

A package can also be represented as:

```
stagekeys://setlist-share?package=<base64url canonical package>
```

The link is limited to 1.5 MB of package data and goes through the same format, checksum, dependency and payload validation as a file. A package over that link budget reports the link limit and directs the user to a `.stagekeyssetlist` file rather than claiming it exceeds the 8 MB file limit. The scheme and host must match exactly and no other query parameters are accepted. File-based sharing remains the baseline; no hosted link service, account or authentication is required or implemented.

## Limits and outstanding acceptance

- This is not a clean-device physical Mac/iPad round-trip qualification. The deterministic suite exercises generated data, not physical devices or an audible stage.
- Independent **sound** exports into a user library remain outstanding for #114. Personal native sound packs already cover sound transfer as a separate format; independent patch exports are implemented as described above.
- Ratings and other library-level metadata are not part of a setlist share; the sender's library metadata is not mutated.
- Reference-only packages do not grant redistribution rights for vendor samples, presets or plug-ins. Install content you are authorised to use on the destination device.
- A successful import does not guarantee that a later graph or Audio Unit installation succeeds; live admission and failure handling remain the existing runtime safeguards.

## Regression coverage

`Tests/SetlistShareTests.swift` is part of the default library gate. It covers:

- checksum/version/format and size refusal, malformed/truncated/altered packages;
- plug-in-state injection and hidden-dependency refusal;
- exclusion of sample payloads, `pluginState` and local source paths;
- offline link round-trip, link-size refusal, and malformed/wrong-host/duplicate-parameter links;
- unavailable-dependency planning and external MIDI warnings;
- identity preservation, name/identity collision resolution and independent copies;
- legacy schema upgrade, atomic writes and refusal to overwrite via an invalid export;
- independent patch export into the library: fresh identities, preserved authored settings, source isolation after later edits, and a repeated export adding a second document instead of overwriting.

The test was authored in a Linux checkout without Xcode. Run it on macOS with:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-share
```

No passing result is claimed here until that command has run. Physical Mac/iPad round-trips, native UI interaction and audible/live-stage checks remain open in [#114](https://github.com/WorshipWarehouse/StageKeys/issues/114).
