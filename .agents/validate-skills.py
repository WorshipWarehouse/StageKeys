#!/usr/bin/env python3
"""Validate the repository's plain name/description skill subset and local links.

No external dependencies; not a substitute for the actual Freebuff loader.
"""
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote

EXPECTED = '''stagekeys-issue-execution stagekeys-architecture swift-apple-development
realtime-audio-dsp midi-integration performance-engine persistence-and-conversion
ui-ux-validation testing-and-debugging reference-behavior-analysis github-issue-management
multi-agent-safety release-validation audio-unit-hosting swift-c-interop
xcode-build-automation audio-performance-profiling rea-reference-investigation'''.split()

def validate(root):
    errors = []
    paths = sorted((root / 'skills').glob('*/SKILL.md'))
    actual = {p.parent.name for p in paths}
    if actual != set(EXPECTED):
        errors.append(f'skill inventory mismatch: missing={set(EXPECTED)-actual}, extra={actual-set(EXPECTED)}')
    for p in paths:
        content = p.read_text()
        if not content.startswith('---\n') or '\n---\n' not in content[4:]:
            errors.append(f'{p}: missing plain frontmatter'); continue
        front, body = content[4:].split('\n---\n', 1)
        # This framework intentionally uses a plain name and JSON-quoted YAML
        # description. Restricting that subset avoids pretending to parse YAML.
        lines = front.splitlines()
        if len(lines) != 2 or not lines[0].startswith('name: ') or not lines[1].startswith('description: '):
            errors.append(f'{p}: unsupported metadata subset'); continue
        name = lines[0][6:]
        try:
            desc = json.loads(lines[1][13:])
        except (ValueError, TypeError):
            errors.append(f'{p}: description must be JSON-quoted YAML string'); continue
        if name != p.parent.name or len(name) > 64 or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', name):
            errors.append(f'{p}: invalid or mismatched name')
        if not isinstance(desc, str) or not 1 <= len(desc) <= 1024:
            errors.append(f'{p}: invalid description')
        if len(body.split()) < 100 or re.search(r'\b(?:TODO|TBD|PLACEHOLDER)\b', body):
            errors.append(f'{p}: empty or unfinished skill')
    for p in root.rglob('*.md'):
        for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', p.read_text()):
            if re.match(r'[a-z]+://', target) or target.startswith('#'):
                continue
            link = (p.parent / unquote(target.split('#')[0])).resolve()
            if not link.exists():
                errors.append(f'{p}: missing link {target}')
    return errors

if __name__ == '__main__':
    root = Path(__file__).resolve().parent
    errors = validate(root)
    for error in errors:
        print('FAIL:', error, file=sys.stderr)
    if errors:
        sys.exit(1)
    print(f'PASS: {len(EXPECTED)} skills, restricted metadata, substantive bodies and local Markdown links')
