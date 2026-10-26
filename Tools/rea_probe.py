#!/usr/bin/env python3
"""Read-only evidence probe for MainStage / channel-strip analysis.

StageKeys keeps observed facts separate from inferences (AGENTS.md). This tool
records one artifact as a machine-checkable record and can capture REA's
artifact inventory as supporting evidence.

    python3 Tools/rea_probe.py probe <artifact> --out <private-dir> \
        --application "Sunday Keys 2.5.2 (MainStage)" --application-version 2.5.2 \
        --license-scope "Demo Mode" \
        --authorization "user-owned local installation; interoperability review"
    python3 Tools/rea_probe.py verify <record.json>

It never writes to the artifact, never instantiates archived classes, and
refuses artifacts inside the repository outside the gitignored Analysis/ folder.
A record is not proof of field meaning, routing or sonic equivalence; it is a
reproducible starting point for that comparison.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCHEMA = "stagekeys-rea-evidence/1"
TOOL_VERSION = "1"
PRIVATE_DIR = "Analysis"
MAX_SCAN_BYTES = 32 * 1024 * 1024
MAX_DIR_FILES = 20000
MAX_HITS = 200

# Literals already used by Sources/MainStagePatch.swift and the EXS reader.
# They are recorded as byte observations, never as decoded field meaning.
DEFAULT_MARKERS = {
    "channel-strip container": b"OCuA",
    "channel-strip device": b"UCuA",
    "sampler host record": b"MELCPMAS1MAS",
    "smart-control mapping": b"MAPlugInParameterMapping",
    "baseplate mapping": b"MABaseplateParameterMapping",
    "exs device label": b"EXS24",
    "binary plist": b"bplist00",
    "xml plist": b"<?xml",
}


class ProbeError(Exception):
    pass


def repo_root(start: Path) -> Path | None:
    for candidate in [start, *start.parents]:
        if (candidate / ".git").exists():
            return candidate
    return None


def private_location(path: Path, root: Path | None, what: str) -> None:
    """Refuse repository paths that are not the gitignored Analysis/ workspace."""
    if root is None:
        return
    try:
        relative = path.resolve().relative_to(root)
    except ValueError:
        return
    if not relative.parts or relative.parts[0] != PRIVATE_DIR:
        raise ProbeError(
            f"{what} {path} is inside the repository. Keep artifacts and records in a "
            f"private folder outside it, or under the gitignored {PRIVATE_DIR}/ workspace."
        )


def sha256_file(path: Path, limit: int | None = None) -> tuple[str, int]:
    digest = hashlib.sha256()
    read = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            if limit is not None and read + len(chunk) > limit:
                chunk = chunk[: limit - read]
            digest.update(chunk)
            read += len(chunk)
            if limit is not None and read >= limit:
                break
    return digest.hexdigest(), read


def marker_hits(data: bytes, markers: dict[str, bytes]) -> list[dict]:
    found = []
    for label, marker in markers.items():
        offsets: list[int] = []
        start = 0
        while len(offsets) < MAX_HITS:
            index = data.find(marker, start)
            if index < 0:
                break
            offsets.append(index)
            start = index + 1
        if offsets:
            found.append({"marker": label, "bytes_hex": marker.hex(), "offsets": offsets})
    return found


def run_rea(command: list[str], artifact: Path, out_dir: Path, stem: str) -> dict:
    """Capture REA's own Evidence; both a refusal and a failure are recorded, not hidden."""
    executable = command[0] if command else "rea"
    resolved = shutil.which(executable) if not os.path.isabs(executable) else executable
    if not resolved or not Path(resolved).exists():
        return {
            "available": False,
            "detail": f"{executable} was not found; install REA per Docs/REA-WORKFLOW.md",
            "commands": [],
        }
    # inspect-artifact needs a recognized format or an app bundle; the entropy probe
    # accepts any file, so opaque channel strips still produce digest-bound Evidence.
    probes = ["inspect-artifact"] if artifact.is_dir() else ["inspect-artifact", "inspect-byte-entropy"]
    commands = []
    for probe in probes:
        argv = [*command, probe, str(artifact), "--format", "json"]
        entry = {"probe": probe, "argv": argv}
        try:
            completed = subprocess.run(argv, capture_output=True, text=True, timeout=900, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            entry.update({"exit": None, "detail": f"REA probe failed: {error}"})
            commands.append(entry)
            continue
        captured = completed.stdout
        bundle = out_dir / f"{stem}.rea-{probe}.json"
        bundle.write_text(captured, encoding="utf-8")
        entry.update(
            {
                "exit": completed.returncode,
                "stdout_sha256": hashlib.sha256(captured.encode("utf-8")).hexdigest(),
                "stdout_bytes": len(captured),
                "stdout_head": captured[:2000] + ("…" if len(captured) > 2000 else ""),
                "stderr_head": completed.stderr[:1000],
                "evidence_file": bundle.name,
            }
        )
        commands.append(entry)
    return {"available": True, "commands": commands}


def directory_inventory(root: Path) -> tuple[dict, list[dict]]:
    counts: dict[str, int] = {}
    total = 0
    scanned = 0
    hits: list[dict] = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            continue
        if path.is_file():
            counts[path.suffix.lower() or "<none>"] = counts.get(path.suffix.lower() or "<none>", 0) + 1
            try:
                size = path.stat().st_size
            except OSError:
                continue
            total += size
            if len(counts) and sum(counts.values()) > MAX_DIR_FILES:
                break
            if scanned < 4000 and 0 < size <= 4 * 1024 * 1024:
                scanned += 1
                try:
                    data = path.read_bytes()
                except OSError:
                    continue
                for hit in marker_hits(data, DEFAULT_MARKERS):
                    if len(hits) >= MAX_HITS:
                        break
                    hits.append({"file": str(path.relative_to(root)), **hit})
    inventory = {
        "files_by_extension": dict(sorted(counts.items())),
        "total_bytes": total,
        "scanned_files": scanned,
    }
    return inventory, hits


def build_record(args: argparse.Namespace) -> dict:
    artifact = Path(args.artifact).expanduser()
    if artifact.is_symlink():
        raise ProbeError("Refusing a symbolic link; point at the real artifact.")
    if not artifact.exists():
        raise ProbeError(f"{artifact} does not exist")
    root = repo_root(Path.cwd().resolve())
    private_location(artifact, root, "Artifact")

    out_dir = Path(args.out).expanduser()
    private_location(out_dir, root, "Output directory")
    out_dir.mkdir(parents=True, exist_ok=True)
    if not out_dir.is_dir():
        raise ProbeError(f"{out_dir} is not a directory")

    observations: list[dict] = []
    limitations = [
        "Byte-level observations only: they do not establish field meaning, record layout, routing or sonic equivalence.",
        "No archived Objective-C class was instantiated, no plug-in was loaded and no MainStage process was launched.",
    ]

    if artifact.is_dir():
        inventory, hits = directory_inventory(artifact)
        stem = f"{artifact.name}-dir"
        target = {
            "kind": "directory",
            "path": str(artifact.resolve()),
            "name": artifact.name,
            "bytes": inventory["total_bytes"],
            "sha256": None,
        }
        observations.append(
            {
                "id": "obs-01",
                "statement": "Directory inventory (bounded scan of regular files).",
                "method": "inventory",
                "evidence": inventory,
            }
        )
        if hits:
            observations.append(
                {
                    "id": "obs-02",
                    "statement": "Known StageKeys/EXS literals found inside the directory.",
                    "method": "byte-scan",
                    "evidence": {"hits": hits, "bounded_to": MAX_HITS},
                }
            )
        limitations.append(
            f"Directory scan read at most {inventory['scanned_files']} files of 4 MiB or less; "
            "absence of a literal is not proof of absence."
        )
    else:
        size = artifact.stat().st_size
        digest, hashed = sha256_file(artifact)
        stem = f"{artifact.stem}-{digest[:8]}"
        target = {
            "kind": "file",
            "path": str(artifact.resolve()),
            "name": artifact.name,
            "bytes": size,
            "sha256": digest,
        }
        observations.append(
            {
                "id": "obs-01",
                "statement": "Artifact bytes hashed.",
                "method": "sha256",
                "evidence": {"sha256": digest, "bytes_hashed": hashed, "bytes": size},
            }
        )
        head_length = min(size, 4096)
        with artifact.open("rb") as handle:
            head = handle.read(head_length)
        observations.append(
            {
                "id": "obs-02",
                "statement": "Leading bytes of the artifact.",
                "method": "bytes",
                "evidence": {
                    "length": head_length,
                    "hex": head[:64].hex(),
                    "ascii": "".join(chr(b) if 32 <= b < 127 else "." for b in head[:64]),
                },
            }
        )
        scan_length = min(size, args.max_scan_bytes)
        with artifact.open("rb") as handle:
            data = handle.read(scan_length)
        markers = dict(DEFAULT_MARKERS)
        for extra in args.marker or []:
            markers[f"caller marker {extra}"] = extra.encode("utf-8")
        hits = marker_hits(data, markers)
        observations.append(
            {
                "id": "obs-03",
                "statement": "Known StageKeys/EXS literals found in the scanned region.",
                "method": "byte-scan",
                "evidence": {"scanned_bytes": scan_length, "hits": hits},
            }
        )
        if scan_length < size:
            limitations.append(
                f"Only the first {scan_length} of {size} bytes were scanned; later literals are unobserved."
            )

    record = {
        "schema": SCHEMA,
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "producer": {"tool": "Tools/rea_probe.py", "version": TOOL_VERSION},
        "host": {
            "platform": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "target": target,
        "provenance": {
            "application": args.application,
            "application_version": args.application_version,
            "license_scope": args.license_scope,
            "authorization": args.authorization,
            "notes": args.notes,
            "collector": args.collector,
        },
        "observations": observations,
        "inferences": [],
        "open_questions": args.question or [],
        "rea": run_rea(shlex.split(args.rea_command), artifact, out_dir, stem) if args.rea_command else {
            "available": None,
            "detail": "REA capture not requested (--rea-command).",
            "commands": [],
        },
        "limitations": limitations,
    }

    record_path = out_dir / f"{stem}.evidence.json"
    if record_path.exists():
        raise ProbeError(f"{record_path} already exists; choose another output folder.")
    handle, temporary = tempfile.mkstemp(dir=out_dir, suffix=".tmp")
    with os.fdopen(handle, "w", encoding="utf-8") as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write("\n")
    os.replace(temporary, record_path)
    return {"record": str(record_path), "observations": len(record["observations"]), "target": target}


def verify_record(path: Path) -> list[str]:
    problems: list[str] = []
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"unreadable record: {error}"]

    if record.get("schema") != SCHEMA:
        problems.append(f"schema must be {SCHEMA}")

    provenance = record.get("provenance") or {}
    for field in ("application", "license_scope", "authorization"):
        value = provenance.get(field)
        if not isinstance(value, str) or not value.strip():
            problems.append(f"provenance.{field} must be a non-empty string")

    target = record.get("target") or {}
    if target.get("kind") == "file":
        if not re.fullmatch(r"[0-9a-f]{64}", str(target.get("sha256"))):
            problems.append("target.sha256 must be 64 lowercase hex characters")
    elif target.get("kind") != "directory":
        problems.append("target.kind must be file or directory")
    if not target.get("path"):
        problems.append("target.path is required")
    else:
        root = repo_root(Path.cwd().resolve())
        try:
            private_location(Path(target["path"]), root, "Recorded artifact")
        except ProbeError as error:
            problems.append(str(error))

    observations = record.get("observations")
    if not isinstance(observations, list) or not observations:
        problems.append("observations must be a non-empty list")
        observation_ids: set[str] = set()
    else:
        observation_ids = set()
        for index, observation in enumerate(observations):
            label = f"observations[{index}]"
            identifier = observation.get("id")
            if not identifier:
                problems.append(f"{label}.id is required")
            elif identifier in observation_ids:
                problems.append(f"{label}.id {identifier} is duplicated")
            else:
                observation_ids.add(identifier)
            if not str(observation.get("statement") or "").strip():
                problems.append(f"{label}.statement must be non-empty")
            if not str(observation.get("method") or "").strip():
                problems.append(f"{label}.method must be non-empty")
            evidence = observation.get("evidence")
            if not isinstance(evidence, dict) or not evidence:
                problems.append(f"{label}.evidence must be a non-empty object")

    for index, inference in enumerate(record.get("inferences") or []):
        label = f"inferences[{index}]"
        if not str(inference.get("statement") or "").strip():
            problems.append(f"{label}.statement must be non-empty")
        cited = inference.get("observations") or []
        if not cited:
            problems.append(f"{label} cites no observation; unsupported inference")
        for identifier in cited:
            if identifier not in observation_ids:
                problems.append(f"{label} cites unknown observation {identifier!r}")

    for index, command in enumerate((record.get("rea") or {}).get("commands") or []):
        if not isinstance(command.get("argv"), list) or not command["argv"]:
            problems.append(f"rea.commands[{index}].argv must be a non-empty list")
        if not isinstance(command.get("exit"), int):
            problems.append(f"rea.commands[{index}].exit must be an integer")
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only REA-backed evidence probe for StageKeys analysis.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe = subparsers.add_parser("probe", help="record one artifact as evidence")
    probe.add_argument("artifact")
    probe.add_argument("--out", required=True, help="private output folder")
    probe.add_argument("--application", required=True, help='e.g. "Sunday Keys 2.5.2 (MainStage)"')
    probe.add_argument("--application-version", default="unknown")
    probe.add_argument("--license-scope", required=True, help='e.g. "Demo Mode", "licensed", "third-party AU"')
    probe.add_argument("--authorization", required=True, help="who authorized this analysis and for what")
    probe.add_argument("--notes", default="")
    probe.add_argument("--collector", default="")
    probe.add_argument("--question", action="append", help="open question this probe is meant to inform")
    probe.add_argument("--marker", action="append", help="extra literal to scan for (repeatable)")
    probe.add_argument("--max-scan-bytes", type=int, default=MAX_SCAN_BYTES)
    probe.add_argument(
        "--rea-command",
        help='quoted REA executable and fixed arguments, e.g. --rea-command "npx -y rea-agents@6.8.0"',
    )

    verify = subparsers.add_parser("verify", help="check records against the evidence rules")
    verify.add_argument("record", nargs="+", help="one or more record files")

    args = parser.parse_args(argv)
    try:
        if args.command == "probe":
            if args.max_scan_bytes <= 0 or args.max_scan_bytes > MAX_SCAN_BYTES:
                raise ProbeError(f"--max-scan-bytes must be between 1 and {MAX_SCAN_BYTES}")
            result = build_record(args)
            print(json.dumps(result, indent=2, sort_keys=True))
            print("\nNext: record inferences with cited observation ids, then run verify.", file=sys.stderr)
            return 0
        failed = False
        for record in args.record:
            problems = verify_record(Path(record))
            if problems:
                failed = True
                for problem in problems:
                    print(f"FAIL {record}: {problem}", file=sys.stderr)
            else:
                print(f"PASS {record}: evidence record is well formed")
        return 1 if failed else 0
    except ProbeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
