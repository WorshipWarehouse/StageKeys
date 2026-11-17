# Nord `.npno` support contract — version 1

Refs #211. This is the support policy and the bound for StageKeys' read-only inspection of Nord
piano files (`.npno`). It is deliberately narrow: no sample is decoded, no sound is created, no
file is written, and nothing here is described as playable.

Contract version: **1** (2026-11-17). A later increment that understands more of the container
must publish version 2 and say what changed; this document is not edited to claim more than the
code below it does.

## What is accepted

`Sources/NpnoPreflight.swift` accepts a file only when all three observed tags match:

| Offset | Bytes | Meaning here | Status |
| --- | --- | --- | --- |
| 0 | `CBIN` | container signature | observed in both private examples |
| 4 | four unidentified bytes | none assigned | unknown; never read as a version |
| 8 | `npno` | piano type tag | observed in both private examples |
| 44 | `CNSP` | content-section tag | observed in both private examples |

Those are observations from the header bytes of the owner's Astoria Grand XL 6.1 and EP9
Stockholm XL 6.0 files, not a published format description. Two similar headers do not specify a
format: no field beyond those four-byte tags is interpreted, no structure is assumed between
offset 12 and offset 44, and the bytes after offset 48 are counted, never parsed. Anything else,
including a different container signature, a non-piano type tag, a content tag at another offset,
a truncated header, or a run of unclassified bytes past the inspection ceiling, is refused rather
than guessed at.

Because no version field has been identified, **no container or stream version is accepted for
decoding**. The only accepted outcome is `inspection-only`; there is no experimental, partial or
verified playback state for `.npno` in this build.

## What the report says

The report carries the input's byte count, the SHA-256 of the unchanged bytes, the classified
spans, the number of unclassified bytes, and the state. It is inspection evidence only:

- the report is never given a playable or converted label;
- the input is opened read-only and its hash is unchanged by inspection;
- every **admission** refusal — container, type, layout, truncation, the input ceiling, the
  unclassified-payload ceiling and the span checks — is raised before any digest is taken, so an
  oversized, malformed or over-ceiling file is never read into a hash;
- the digest then streams the **same opened file** from its start and refuses a length change, and
  the classified prefix is re-read from that same handle afterwards and compared byte for byte. Any
  difference is `inputChanged`. These consistency checks can only be decided while reading or after
  the prefix is re-read, so they are not admission refusals: they replace the report instead of
  publishing a digest taken from a different read than the one that was classified;
- a same-length rewrite inside the classified prefix is therefore refused, but a same-length rewrite
  of bytes *past* the prefix is not detected — those bytes are described by length only, and the
  digest reports the content that was actually read for them.

Spans are the three four-byte tags. Every gap between them is reported as `unclassified`, including
the four unidentified bytes at offset 4 that sit between the container and type tags. A span that leaves the input, overlaps another span, is empty, or
pushes the report past its span limit is a refusal — the same validator a later version parser
must use before it trusts any offset it finds inside those bytes.

## Limits

| Limit | Value | Refusal |
| --- | --- | --- |
| `maximumFileBytes` | 64 MiB | `oversizedInput` |
| `maximumUnclassifiedBytes` | 48 MiB | `unclassifiedPayloadTooLarge` |
| `maximumReadBytes` | 64 bytes | `unsupportedLayout` if the tags cannot be read |
| `maximumSpans` | 8 | `tooManySpans` |
| streamed length | equals the classified size, with no trailing byte | `inputChanged` |

Additional refusals: `empty`, `truncated` (below 48 bytes), `unexpectedContainer`,
`unexpectedType`, `unexpectedLayout`, `overlappingSpan`, `spanOutOfRange`. A read limit too small
to reach the observed content tag is refused as `unsupportedLayout` — a limit violation is never
reported as a wrong container or type.

Reading from disk uses the file size first and then reads at most `maximumReadBytes`, so a large
file is refused before its payload is touched. The digest reads the same handle in 1 MiB chunks and
never exceeds the classified size.

## Out of scope for this pathway

These are refused or simply not offered, and no code path here starts them:

- `.nsmp` samples, and Multi Sample / program / effect / organ / synth files — separate formats
  with separate evidence;
- decoding the sample stream, mapping multisamples into an instrument, importing, exporting or
  transferring anything (#212–#214);
- any USB or network transfer to or from a Nord instrument;
- playback, gain staging, velocity behaviour or any sonic-parity claim (#215–#216);
- any write, repair, or re-save of a `.npno` file. Nothing in this increment writes.

The reader is not reachable from the library import path yet: the picker, the preflight report and
the refusal message in the UI belong to the import increment (#214), because there is nothing a
user could do with an inspection-only result before then.

## Provenance and licensing

Candidate references were recorded, not adopted:

- `nord-format` 0.9.0 (`docs.rs`) — candidate struct reading, not validated;
- OpenNord documentation and `simonflore/opennord` — candidate reading material. **OpenNord is
  AGPL-3.0; no code from it is copied into this MIT-licensed app**, and nothing here is derived
  from it. Reusing any part needs an explicit licensing decision from the owner first.
- No third-party parser or decoder is vendored, linked or added as a dependency by this
  increment, so there is no new attribution obligation beyond the existing project notices.

The two private piano files are verification inputs only. Their bytes, decoded samples and any
derived reports are not committed, not packaged and not uploaded; public tests use synthetic
fixtures generated in `Tests/NpnoPreflightTests.swift`.

## Content terms

| Use | Status |
| --- | --- |
| Inspecting the owner's own files locally | allowed, read-only, hash preserved |
| Exporting or redistributing a `.npno` or a decoded piano | **unknown**; not implemented, not claimed |
| Cloud transfer or automatic upload | **unknown**; not implemented, no factory library is bundled |

Redistribution and upload permission for Nord content is unresolved and is an owner decision, not
a conclusion this document draws.

## What this increment does not prove

- No sanitized report for the two private examples is committed here: those files are not in this
  workspace and their bytes must not enter the repository. The reports are produced locally by the
  same code path and stay outside version control.
- No sample codec, note mapping, velocity layer or loop behaviour is verified or claimed (#212).
- The two tag offsets and the counts above are the whole of the format knowledge this build acts
  on.
