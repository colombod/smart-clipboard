#!/usr/bin/env python3
"""Publication guard tests. All signing, Keychain, network and gh calls are fakes."""
import base64
import importlib.util
import json
import pathlib
import plistlib
import tempfile
import types
import unittest
import sys
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('release_update', pathlib.Path(__file__).parents[2] / 'scripts/release-update.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.patch = patch.object(release, 'REPO', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.calls = []
        self.public_key = base64.b64encode(bytes(32)).decode()
        self.signature = base64.b64encode(bytes(64)).decode()
        self.args = types.SimpleNamespace(tag='v0.4.0-preview.11', channel='preview',
            approve_stable=False, notes=self.root / 'notes.txt', sparkle_tools=self.root / 'tools',
            account='fixture-account', first_feed=True)
        self.args.notes.write_text('Preview: native accessibility acceptance remains incomplete.\n')
        dist = self.root / 'dist'
        app = dist / 'Smart Clipboard.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/MacOS/SmartClipboard').write_bytes(b'signed fixture')
        self.app_hash = release.sha(app / 'Contents/MacOS/SmartClipboard')
        info = {'CFBundleIdentifier': 'com.smartclipboard.app', 'CFBundleShortVersionString': '0.4.0',
                'CFBundleVersion': '11', 'SUFeedURL': release.FEED, 'SUPublicEDKey': self.public_key,
                'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True, 'LSMinimumSystemVersion': '14.0'}
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        state = dist / 'notarization-release'
        state.mkdir()
        (state / 'complete').touch()
        (state / 'app.sha256').write_text(self.app_hash)
        entries = []
        for ext, state_name in [('zip', 'zip.sha256'), ('dmg', 'dmg-final.sha256')]:
            asset = dist / f'Smart-Clipboard-0.4.0-macOS-arm64.{ext}'
            asset.write_bytes(ext.encode())
            (state / state_name).write_text(release.sha(asset))
            entries.append(f'{release.sha(asset)}  {asset.name}\n')
        (dist / 'SHA256SUMS.txt').write_text(''.join(entries))
        (dist / 'build-source.json').write_text(json.dumps({'commit': 'a' * 40, 'dirty': False, 'executableSHA256': self.app_hash}))

    def fake_run(self, *args, **kwargs):
        args = tuple(str(a) for a in args)
        self.calls.append(args)
        if args[0].endswith('/generate_keys'):
            self.assertEqual(args[1:], ('--account', 'fixture-account', '-p'))
            return self.public_key + '\n'
        if args[0].endswith('/sign_update') and '-p' in args:
            return self.signature + '\n'
        return ''

    def prepare(self, download=None):
        with patch.object(release, 'run', side_effect=self.fake_run), \
             patch.object(release, 'source_state', return_value=('a' * 40, '')), \
             patch.object(release, 'download', side_effect=download or (lambda *a, **kw: False)):
            release.prepare(self.args)
        return release.verify_local()

    def test_preview_signs_archive_and_feed_without_exporting_key(self):
        output, manifest = self.prepare()
        item = ET.parse(output / 'appcast.xml').find('channel/item')
        self.assertEqual(item.findtext(f'{{{release.NS}}}channel'), 'preview')
        self.assertEqual(item.findtext(f'{{{release.NS}}}version'), '11')
        self.assertEqual(item.find('enclosure').get(f'{{{release.NS}}}edSignature'), self.signature)
        self.assertEqual(manifest['channel'], 'preview')
        self.assertTrue(any('--verify' in call and call[-1] == self.signature for call in self.calls))
        self.assertTrue(any(call[0].endswith('/sign_update') and call[-1].endswith('appcast.xml') and '--verify' in call for call in self.calls))
        self.assertFalse(any('-x' in call or '--ed-key-file' in call or '-s' in call for call in self.calls))

    def test_stable_needs_explicit_acceptance_and_has_no_channel(self):
        self.args.channel = 'stable'
        self.args.tag = 'v0.4.0'
        with self.assertRaisesRegex(ValueError, 'approve-stable'):
            self.prepare()
        self.args.approve_stable = True
        output, _ = self.prepare()
        self.assertIsNone(ET.parse(output / 'appcast.xml').find('channel/item').find(f'{{{release.NS}}}channel'))

    def test_dirty_or_changed_build_cannot_prepare(self):
        with patch.object(release, 'source_state', return_value=('a' * 40, ' M source.swift')):
            with self.assertRaisesRegex(ValueError, 'clean commit'):
                release.prepare(self.args)
        (self.root / 'dist/Smart Clipboard.app/Contents/MacOS/SmartClipboard').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'provenance'):
            self.prepare()

    def test_first_feed_cannot_replace_existing_feed(self):
        with self.assertRaisesRegex(ValueError, 'first-feed'):
            self.prepare(download=lambda *a, **k: True)

    def test_preserves_prior_stable_entry_and_requires_increasing_build(self):
        self.args.first_feed = False
        def previous(url, path, **kwargs):
            path.write_text(f'<rss xmlns:sparkle="{release.NS}"><channel><item><sparkle:version>10</sparkle:version></item></channel></rss>')
            return True
        output, manifest = self.prepare(download=previous)
        self.assertEqual(len(ET.parse(output / 'appcast.xml').findall('channel/item')), 2)
        self.assertIsNotNone(manifest['previousFeedSHA256'])
        channel = ET.fromstring(f'<channel xmlns:sparkle="{release.NS}"><item><sparkle:version>11</sparkle:version></item></channel>')
        with self.assertRaisesRegex(ValueError, 'greater'):
            release.validate_new_build(channel, 11)

    def test_assets_cannot_change_after_preparation(self):
        self.prepare()
        (self.root / 'dist/Smart-Clipboard-0.4.0-macOS-arm64.zip').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'asset changed'):
            release.verify_local()

    def test_annotated_tag_resolves_to_built_commit(self):
        manifest = {'tag': 'v0.4.0-preview.11', 'channel': 'preview', 'commit': 'a' * 40}
        info = {'tagName': manifest['tag'], 'isPrerelease': True}
        refs = f'{"b" * 40}\trefs/tags/{manifest["tag"]}\n{"a" * 40}\trefs/tags/{manifest["tag"]}^{{}}\n'
        with patch.object(release, 'run', return_value=refs):
            release.verify_release_identity(info, manifest)
        with patch.object(release, 'run', return_value=''):
            with self.assertRaisesRegex(ValueError, 'exact reviewed'):
                release.verify_release_identity(info, manifest)

    def test_draft_release_never_reaches_public_download(self):
        with patch.object(release, 'release_info', return_value={'isDraft': True}), \
             patch.object(release, 'verify_release_identity'), patch.object(release, 'download') as download:
            with self.assertRaisesRegex(ValueError, 'still a draft'):
                release.verify_public({})
            download.assert_not_called()

    def test_feed_publication_stops_before_writes_when_assets_unavailable(self):
        _, manifest = self.prepare()
        args = types.SimpleNamespace(approve_tag=manifest['tag'], sparkle_tools=self.args.sparkle_tools)
        with patch.object(release, 'verify_public', side_effect=ValueError('Public asset mismatch')), \
             patch.object(release, 'run') as command, patch.object(release, 'gh_json') as gh:
            with self.assertRaisesRegex(ValueError, 'Public asset'):
                release.publish_feed(args)
            command.assert_not_called()
            gh.assert_not_called()

    def test_changed_public_feed_never_overwritten(self):
        _, manifest = self.prepare()
        args = types.SimpleNamespace(approve_tag=manifest['tag'], sparkle_tools=self.args.sparkle_tools)
        def changed(url, path, **kwargs):
            path.write_bytes(b'new published feed')
            return True
        with patch.object(release, 'verify_public'), patch.object(release, 'require_key'), \
             patch.object(release, 'run', side_effect=self.fake_run), \
             patch.object(release, 'gh_json', return_value={'source': {'branch': 'gh-pages', 'path': '/'}, 'html_url': release.FEED.removesuffix('appcast.xml')}), \
             patch.object(release, 'download', side_effect=changed):
            with self.assertRaisesRegex(ValueError, 'stale overwrite'):
                release.publish_feed(args)
        self.assertFalse(any('--method' in call for call in self.calls))

    def test_public_download_checksum_mismatch_fails(self):
        _, manifest = self.prepare()
        def wrong(url, path, **kwargs):
            path.write_bytes(b'wrong public bytes')
            return True
        with patch.object(release, 'release_info', return_value={'isDraft': False}), \
             patch.object(release, 'verify_release_identity'), patch.object(release, 'download', side_effect=wrong):
            with self.assertRaisesRegex(ValueError, 'Public asset does not match'):
                release.verify_public(manifest)

    def test_feed_write_follows_public_verification_and_requires_unchanged_branch(self):
        _, manifest = self.prepare()
        args = types.SimpleNamespace(approve_tag=manifest['tag'], sparkle_tools=self.args.sparkle_tools)
        events = []
        def command(*args, **kwargs):
            if '--method' in args:
                self.assertIn('public-assets-verified', events)
                events.append('feed-write')
            return ''
        replies = [{'source': {'branch': 'gh-pages', 'path': '/'}, 'html_url': release.FEED.removesuffix('appcast.xml')}, {'tree': []}]
        with patch.object(release, 'verify_public', side_effect=lambda _: events.append('public-assets-verified')), \
             patch.object(release, 'require_key'), patch.object(release, 'run', side_effect=command), \
             patch.object(release, 'gh_json', side_effect=replies), patch.object(release, 'download', return_value=False):
            release.publish_feed(args)
        self.assertEqual(events, ['public-assets-verified', 'feed-write'])

    def test_public_feed_verification_requires_exact_signed_bytes(self):
        _, manifest = self.prepare()
        args = types.SimpleNamespace(sparkle_tools=self.args.sparkle_tools)
        def old(url, path, **kwargs):
            path.write_bytes(b'old CDN feed')
            return True
        with patch.object(release, 'verify_public'), patch.object(release, 'require_key'), \
             patch.object(release, 'run') as command, patch.object(release, 'download', side_effect=old):
            with self.assertRaisesRegex(ValueError, 'does not yet match'):
                release.verify_feed(args)
            command.assert_not_called()

    def test_feed_retry_recognizes_successful_commit_before_pages_deploys(self):
        output, manifest = self.prepare()
        args = types.SimpleNamespace(approve_tag=manifest['tag'], sparkle_tools=self.args.sparkle_tools)
        replies = [{'source': {'branch': 'gh-pages', 'path': '/'}, 'html_url': release.FEED.removesuffix('appcast.xml')},
                   {'tree': [{'path': 'appcast.xml', 'sha': 'branch-blob'}]},
                   {'content': base64.b64encode((output / 'appcast.xml').read_bytes()).decode()}]
        with patch.object(release, 'verify_public'), patch.object(release, 'require_key'), \
             patch.object(release, 'run', side_effect=self.fake_run), patch.object(release, 'gh_json', side_effect=replies), \
             patch.object(release, 'download', return_value=False):
            release.publish_feed(args)
        self.assertFalse(any('--method' in call for call in self.calls))


if __name__ == '__main__':
    unittest.main()
