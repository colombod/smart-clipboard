#!/usr/bin/env python3
"""Offline CLI integration tests; standard library only, no model/server/app calls."""
from pathlib import Path
import argparse, hashlib, json, os, stat, struct, subprocess, tempfile, unittest, zlib
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', type=Path, required=True)
args = parser.parse_args()
BINARY = args.binary.resolve()

def png(width=32, height=16):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    rows = b''.join(b'\0' + b''.join((bytes((20, 80, 210, 255)) if x < width // 2 else bytes((210, 40, 30, 255))) for x in range(width)) for _ in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')

class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.input = self.root / 'input.png'; self.input.write_bytes(png())
        self.output = self.root / 'result.svg'
    def tearDown(self): self.temporary.cleanup()
    def command(self, *extra, preset='photo', detail='balanced'):
        return [str(BINARY), '--input', str(self.input), '--output', str(self.output), '--preset', preset, '--detail', detail, *extra]
    def run_helper(self, command=None):
        return subprocess.run(command or self.command(), capture_output=True, text=True, timeout=15, env={'PATH': '/usr/bin:/bin'})
    def test_version_and_strict_arguments(self):
        r = self.run_helper([str(BINARY), '--version'])
        self.assertEqual(r.returncode, 0); self.assertEqual(json.loads(r.stdout)['version'], '0.6.5')
        for command in [self.command('--preset', 'photo'), self.command('--arbitrary', 'value'), self.command(preset='unknown'), self.command(detail='unknown'), [str(BINARY), '--version', '--help']]:
            self.assertNotEqual(self.run_helper(command).returncode, 0)
        self.assertFalse(self.output.exists())
    def test_release_does_not_embed_build_machine_home_paths(self):
        data = BINARY.read_bytes()
        for prefix in [b'/Users/', b'/home/']:
            self.assertNotIn(prefix, data, 'Release helper includes a build-machine home path')
    def test_presets_produce_bounded_real_paths(self):
        original = hashlib.sha256(self.input.read_bytes()).digest()
        for preset in ['photo', 'logo', 'line-art']:
            for detail in ['balanced', 'detailed']:
                with self.subTest(preset=preset, detail=detail):
                    r = self.run_helper(self.command(preset=preset, detail=detail))
                    self.assertEqual(r.returncode, 0, r.stderr)
                    data = self.output.read_bytes(); info = json.loads(r.stdout)
                    self.assertEqual(info['engine'], 'vtracer'); self.assertEqual(info['bytes'], len(data))
                    svg = ET.fromstring(data); self.assertEqual(svg.attrib['viewBox'], '0 0 32 16')
                    self.assertEqual(len(svg.findall('{http://www.w3.org/2000/svg}path')), info['paths'])
                    self.assertGreater(info['paths'], 0)
                    self.assertTrue(all(e.tag.rsplit('}', 1)[-1] in ['svg', 'path'] for e in svg.iter()))
                    self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
                    self.output.unlink()
        self.assertEqual(hashlib.sha256(self.input.read_bytes()).digest(), original)
    def test_refuses_existing_and_symlink_output(self):
        self.output.write_text('preserve me')
        self.assertNotEqual(self.run_helper().returncode, 0); self.assertEqual(self.output.read_text(), 'preserve me')
        self.output.unlink(); self.output.symlink_to(self.input)
        before = self.input.read_bytes()
        self.assertNotEqual(self.run_helper().returncode, 0); self.assertEqual(self.input.read_bytes(), before)
    def test_refuses_symlink_input_and_nonregular_file(self):
        original = self.root / 'original.png'; self.input.rename(original); self.input.symlink_to(original)
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.input.unlink(); os.mkfifo(self.input)
        self.assertNotEqual(self.run_helper().returncode, 0); self.assertFalse(self.output.exists())
    def test_rejects_bad_or_oversized_input(self):
        for data in [b'not an image', png()[:33], png()[:16] + struct.pack('>II', 8000, 8000) + png()[24:]]:
            self.input.write_bytes(data); r = self.run_helper()
            self.assertNotEqual(r.returncode, 0); self.assertFalse(self.output.exists()); self.assertNotIn(str(self.root), r.stderr)
        with self.input.open('wb') as file: file.truncate(64 * 1024 * 1024 + 1)
        self.assertNotEqual(self.run_helper().returncode, 0); self.assertFalse(self.output.exists())

unittest.main(argv=['test_cli.py'])
