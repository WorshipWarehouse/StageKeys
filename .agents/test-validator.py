#!/usr/bin/env python3
"""Exercise invalid inventory, metadata, names and broken links without dependencies."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('validator', BASE / 'validate-skills.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / '.agents'
        shutil.copytree(BASE, self.root, ignore=shutil.ignore_patterns('__pycache__'))
        self.skill = self.root / 'skills' / 'midi-integration' / 'SKILL.md'

    def test_valid_framework(self):
        self.assertEqual(validator.validate(self.root), [])

    def test_missing_required_skill(self):
        self.skill.unlink()
        self.assertTrue(any('inventory mismatch' in x for x in validator.validate(self.root)))

    def test_mismatched_name(self):
        self.skill.write_text(self.skill.read_text().replace('name: midi-integration','name: another-name',1))
        self.assertTrue(any('mismatched name' in x for x in validator.validate(self.root)))

    def test_invalid_description(self):
        self.skill.write_text(self.skill.read_text().replace('description: "','description: unquoted "',1))
        self.assertTrue(any('description must' in x for x in validator.validate(self.root)))

    def test_dangling_resource(self):
        self.skill.write_text(self.skill.read_text()+'\n[required resource](missing.md)\n')
        self.assertTrue(any('missing link missing.md' in x for x in validator.validate(self.root)))

if __name__ == '__main__':
    unittest.main()
