# Nord piano libraries (`.npno`): support contract v1

This original inspection contract accompanies the bounded, read-only preflight in
`Sources/NordPiano.swift` (issue #211). It deliberately covers **inspection only**.
Inspection alone never labels a file playable. The subsequent experimental
decoder, attack-only mapping and transactional import are specified separately in
[NORD-NATIVE-VALIDATION.md](NORD-NATIVE-VALIDATION.md).

## Scope

| Item | State |
| --- | --- |
| `.npno` container and metadata prefix, read-only | Experimental, bounded preflight |
| Sample decoding | Bounded integer decoder, see native validation (#212) |
| Layer selection / loops / pedals | Partial native translation with explicit differences (#213) |
| Mapping into a native StageKeys instrument | Experimental attack-only translation (#213) |
| Transactional import and personal-pack export | Implemented software path; physical transfer unqualified (#214/#216) |
| `.nsmp`, Nord programs, effects, organ/synth emulation, USB transfer | Out of scope |

Accepted input is a CBIN container whose tag is `npno` and whose body starts with
a `CNSP` stream at a documented version (`0x450` or `0x464`). Any other version,
container generation or tag is refused rather than guessed.

## Field provenance

The format description used here is the public documentation for the independent
`nord-format` Rust crate (`https://docs.rs/nord-format/0.9.0/`, module
`nord_format::formats::npno` and `nord_format::cbin`). The initial preflight used field descriptions only. The subsequent stroke parser,
codec and velocity selector adapt the BSD-3-Clause `nord-format` implementation
from jmoo/drawbar tree `210472d0b462a663a731b44966f478f50ce8a091`;
`Licenses/Drawbar-BSD-3-Clause.txt` preserves John Moore’s notice and is bundled
on both Apple targets. No upstream audio fixtures were copied. Confidence labels below are the ones that
documentation attaches to each fact.

| Fact | Value used | Provenance |
| --- | --- | --- |
| Container magic | `CBIN` at 0x00 | Confirmed on hardware (type 1) |
| Generation word | LE `u32` at 0x04: 0 or 1 | Confirmed on hardware (type 1); type 0 inferred from specimens |
| Format tag | 4 bytes at 0x08, `npno` | Confirmed on hardware (type 1) |
| Content version | LE `u32` at 0x14 | Confirmed on hardware (type 1) |
| Type-1 layout | body CRC32 at 0x18, 16 zero bytes, body at 0x2c | Confirmed on hardware |
| Type-0 layout | body at 0x18, `crc16` at EOF−2 over all earlier bytes | Inferred from specimens |
| Body stream magic | `CNSP` at body offset 0x00 | Inferred from specimens |
| Stream version | BE `u16` at 0x04, echoed at 0x61c | Inferred from specimens |
| Name / variant / voicing | NUL-padded text at 0x1c, 0x3c, voicing at 0x5c (`0x464` only) | Inferred from specimens |
| Key map | 128 bytes at 0x8c, `0xFF` = uncovered | Inferred from specimens |
| Channel count | BE `u16` at 0x61e, 1 or 2 | Inferred from specimens |
| Stroke count | BE `u16` at 0x620 | Inferred from specimens |
| Per-root stroke counts | 128 × BE `u16` at 0x622, summing to the stroke count | Inferred from specimens |
| Stroke directory | `N` × 118-byte records at 0x732 | Inferred from specimens |
| Audio region | follows the directory, whole `1022 × channels` blocks, first span on a grid minus 192 bytes, gap before it zero | Confirmed on hardware (layout); the 192-byte bias is *unexplained* |

The prefix offsets are explicitly marked "inferred from specimens; not confirmed
on hardware" upstream. This reader therefore validates them only against the two
documented stream versions and reports rather than repairs anything else.

## What the preflight checks

- Size and header bounds before any field is read; input larger than the limit is
  refused without touching it.
- Container magic, generation word, `npno` tag and the type-1 body CRC32.
- `CNSP` magic, accepted stream version and its echoed copy.
- Channel count, stroke count, the per-root count table sum, and that the stroke
  directory fits inside the body.
- The documented audio grid: aligned start inside the body, zero gap, and a whole
  number of blocks of audio.
- NUL-padded text fields, rejecting control bytes instead of guessing and requiring the bytes after the terminator to be zero or a space.
- The bounded file-size limit and the stroke limit apply to the raw-buffer entrypoint as well as the `Data` one, so neither caller can skip admission.
- Exposes covered-key count, audio start/length and the block size for a later
  mapping step (#213).

It does **not** validate each stroke's own span length (the record's block-count
field offsets are not part of the published offset table used here), and it does
not interpret the header `location`/`aux` words, which upstream notes hold
something other than a bank and slot in a library. Both are reported in the
result's notes.

## Refusals and limits

Truncated files, wrong magic/tag, unsupported generation or stream version,
non-matching version echo, invalid channel or stroke counts, count-table
mismatches, directory overflow, a non-zero alignment gap, missing audio and
non-block-aligned audio are rejected with a specific reason. Default limits are
512 MiB and 4096 strokes; the reader works over the caller's bytes and copies no
body data.

The container checksum is reported as `verified`, `mismatch` or `unestablished`.
A mismatch is surfaced for review rather than silently accepted; the type-0
`crc16` is `unestablished` because its polynomial and covered byte order are only
inferred, and rejecting real files on an inferred algorithm would be worse than
reporting that it was not checked.

## Provenance, licensing and content terms

- Upstream `nord-format` is BSD-3-Clause, copyright 2023–2026 John Moore.
  Its retained notice covers the adapted stroke layout, decoder and measured
  velocity selector; StageKeys authorship does not relicense that material.
  OpenNord is AGPL-3.0 and G1-Emu GPL-3.0; neither implementation was copied.
  The supplied `nordstage/ns4decode` URL returned 404 on 17 November 2026.
- The two owner-selected examples (Astoria Grand XL 6.1 and EP9 Stockholm XL 6.0)
  are private verification inputs, not redistributable fixtures. Public tests use
  only the synthetic fixtures in `Tests/NordPianoInspectionTests.swift`.
- Personal local inspection is the only use this contract assumes. Export and
  cloud transfer terms for Nord-authored content remain **unknown**; no factory
  library is bundled, uploaded or inferred to be redistributable.
- No decrypting or access-control bypass is performed or planned. Unknown
  container, codec or musical semantics are reported as unknown.

## Private-example reports

Both owner-selected inputs were inspected locally on 17 November 2026. The original
preflight added the grid bias instead of subtracting it; authentic files caught
that error and the independent synthetic grid assertions now cover the correction.

| Input | Bytes | SHA256 | Stream / content | Channels | Strokes | Directory end / first audio (body offsets) | CRC32 |
| --- | ---: | --- | --- | ---: | ---: | --- | --- |
| Astoria Grand XL 6.1.npno | 218673104 | `6b43e12ce6345ec9a45c546fb30aff0970d13742d1016fe28fd593f34fd6b57c` | 0x464 / 610 | 2 | 1558 | 185686 / 185812 | verified 0xf4c30571 |
| EP9 Stockholm XL 6.0.npno | 105794226 | `5e72678d8cc2c760aa6485e9bb9b760013e5f09c2198c19ff37837490fa842ae` | 0x464 / 600 | 1 | 2196 | 260970 / 261440 | verified 0xbdb042a2 |

Both cover 109 keys. All directory spans are validated by the later `index` entry
point, all source strokes decode with exact overlap/frame counts and no clipping,
and every stored middle-C attack layer is checked. Astoria banks: 589 attack,
589 resonance, 380 release. Stockholm: 1465 attack, 731 release. Aggregate decoded
PCM: 790936272 and 444601356 bytes respectively. These are private local evidence,
not redistributable fixtures or hardware/Nord listening comparisons. The full
production-path audit and outstanding device criteria are in the native validation
record. No source or derived audio is committed.
