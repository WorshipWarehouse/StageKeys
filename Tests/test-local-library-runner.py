"""Portable tests of plan coverage, failure propagation and explicit fixture skips."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('local_library_runner', repo / 'Tests/run-local-library.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_complete_plan_and_source_files(self):
        sources, swift, native = runner.plan(repo)
        self.assertIn('Sources/EQBandwidth.swift', sources)
        self.assertIn('PluginInterfaceRequestTests', swift)
        self.assertEqual(set(native), {'DelayIndependentLevelsTests', 'AudioEffectsTests', 'ChannelDSPTests', 'ChannelPanicTests', 'RackTests', 'SynthTests', 'MetronomeTests'})
        for name in sources:
            self.assertTrue((repo / name).is_file(), name)
        for names, suffix in [(swift, '.swift'), (native, '.c')]:
            for name in names:
                self.assertTrue((repo / 'Tests' / (name + suffix)).is_file(), name)

    def test_incomplete_and_duplicate_plans_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Tests').mkdir()
            shell = root / 'Tests/test-library.sh'
            shell.write_text('else tests=(Example); fi\n')
            with self.assertRaises(ValueError):
                runner.plan(root)
            shell.write_text('"$repo/Sources/Model.swift"\nelse tests=(Example Example); fi\nfor test in Native; do\n')
            with self.assertRaises(ValueError):
                runner.plan(root)

    def execute(self, outputs):
        with tempfile.TemporaryDirectory() as temporary:
            build = Path(temporary)
            results = []
            with patch.object(runner, 'run_command', side_effect=outputs):
                try:
                    runner.execute_test('Example', ['compile'], build / 'Example', build, results)
                except subprocess.SubprocessError:
                    pass
            saved = json.loads((build / 'results.json').read_text())
            self.assertEqual(saved, results)
            return saved[0]

    def test_exercised_and_skipped_are_distinct(self):
        self.assertEqual(self.execute(['', 'PASS fixture\n'])['status'], 'passed')
        skipped = self.execute(['', 'SKIP: private source unset\n'])
        self.assertEqual(skipped['status'], 'skipped')
        self.assertIsNone(skipped['passed'])
        self.assertEqual(skipped['reasons'], ['SKIP: private source unset'])

    def test_compile_runtime_and_timeout_failures_are_fatal(self):
        for outputs in [
            [subprocess.CalledProcessError(1, ['compile'])],
            ['', subprocess.CalledProcessError(133, ['Example'], output='SKIP then crash')],
            ['', subprocess.TimeoutExpired(['Example'], 300)],
        ]:
            failed = self.execute(outputs)
            self.assertEqual(failed['status'], 'failed')
            self.assertFalse(failed['passed'])
            self.assertIn('error', failed)

    def test_real_command_never_treats_nonzero_as_skip(self):
        failed = subprocess.CompletedProcess(['Example'], 133, stdout='SKIP then crash\n')
        with patch.object(runner.subprocess, 'run', return_value=failed):
            with self.assertRaises(subprocess.CalledProcessError):
                runner.run_command(['Example'])

    def test_explicit_exs_fixture_arguments_are_retained(self):
        self.assertEqual(runner.fixture_args('EXSImportTests', Path('/tmp/build'), {}), [])
        env = {'STAGEKEYS_EXS_FIXTURE': '/fixture/source.exs', 'STAGEKEYS_EXS_ROOT': '/fixture/samples'}
        self.assertEqual(runner.fixture_args('EXSImportTests', Path('/tmp/build'), env),
                         [Path('/tmp/build/exs-scratch'), '/fixture/source.exs', '/fixture/samples'])
        self.assertEqual(runner.fixture_args('Other', Path('/tmp/build'), env), [])

    def test_path_taking_tests_receive_a_private_scratch_location(self):
        with tempfile.TemporaryDirectory() as temporary:
            build = Path(temporary)
            self.assertEqual(runner.scratch_args('AudioGraphTests', build),
                             [build / 'scratch/AudioGraphTests/rendered.wav'])
            self.assertTrue((build / 'scratch/AudioGraphTests').is_dir())
            self.assertEqual(runner.scratch_args('SetlistLibraryTests', build),
                             [build / 'scratch/SetlistLibraryTests'])
            self.assertTrue((build / 'scratch/SetlistLibraryTests').is_dir())
            self.assertEqual(runner.scratch_args('MIDIInputTests', build), [])
            self.assertEqual(runner.scratch_args('ExternalAudioTests', build),
                             [build / 'scratch/ExternalAudioTests'])
            self.assertEqual(runner.scratch_args('SamplerInterchangeTests', build),
                             [build / 'scratch/SamplerInterchangeTests'])
            self.assertEqual(runner.scratch_args('EXSImportTests', build), [])


if __name__ == '__main__':
    unittest.main()
