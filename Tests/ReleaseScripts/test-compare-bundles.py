#!/usr/bin/env python3
"""Regression coverage for packaged framework links and payload changes."""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('compare_bundles', Path(__file__).parents[2] / 'scripts/compare-bundles.py')
bundles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundles)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'source.app'
        self.copy = Path(self.temp.name) / 'copy.app'
        version = self.source / 'Contents/Frameworks/Example.framework/Versions/B'
        version.mkdir(parents=True)
        (version / 'Example').write_bytes(b'framework executable')
        (version.parent / 'Current').symlink_to('B', target_is_directory=True)
        # A cycle must be compared as a link, never traversed by the verifier.
        (version / 'Parent').symlink_to('..', target_is_directory=True)
        self.relative_binary = (version / 'Example').relative_to(self.source)
        shutil.copytree(self.source, self.copy, symlinks=True)

    def test_framework_alias_and_cycle_are_compared_without_traversal(self):
        bundles.compare(self.source, self.copy)

    def test_modified_payload_fails(self):
        (self.copy / self.relative_binary).write_bytes(b'changed executable')
        with self.assertRaisesRegex(ValueError, 'Bundle entries differ'):
            bundles.compare(self.source, self.copy)

    def test_changed_link_fails(self):
        link = self.copy / self.relative_binary.parent / 'Parent'
        link.unlink()
        link.symlink_to('../..', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Parent'):
            bundles.compare(self.source, self.copy)

    def test_missing_and_extra_entries_fail(self):
        (self.copy / self.relative_binary).unlink()
        (self.copy / 'unexpected').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'unexpected'):
            bundles.compare(self.source, self.copy)

    def test_executable_permission_change_fails(self):
        binary = self.copy / self.relative_binary
        binary.chmod(binary.stat().st_mode ^ 0o100)
        with self.assertRaisesRegex(ValueError, 'Example'):
            bundles.compare(self.source, self.copy)

    def test_missing_root_fails(self):
        with self.assertRaisesRegex(ValueError, 'Expected a real bundle directory'):
            bundles.compare(self.source, self.copy / 'absent')


if __name__ == '__main__':
    unittest.main()
