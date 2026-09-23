#!/usr/bin/env python3
"""Isolated help-site resource and publishing-boundary checks; never publishes."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/build-help-site.py"
SPEC = importlib.util.spec_from_file_location("help_site", SCRIPT)
site = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(site)
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6ky8AAAAASUVORK5CYII=")


class HelpSiteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="smart-clipboard-help-test-")
        self.root = Path(self.temporary.name).resolve()
        self.images = self.root / "docs/images"
        self.images.mkdir(parents=True)
        self.readme = self.root / "README.md"
        self.guide = self.root / "docs/USER-GUIDE.md"
        self.icon = self.root / "docs/app-icon.png"
        self.icon.write_bytes(PNG)
        self.readme.write_text("# Smart Clipboard\n\n[Guide](docs/USER-GUIDE.md)\n")
        self.guide.write_text("# Guide\n")
        self.globals = patch.multiple(site, ROOT=self.root, ICON=self.icon,
                                      PAGES={self.readme: "index.html", self.guide: "guide.html"})
        self.globals.start()
        self.addCleanup(self.globals.stop)
        self.addCleanup(self.temporary.cleanup)

    def parse(self, markup):
        resources = {}
        parser = site.PageHTML(self.readme, "v0.4.0-preview.13", {}, resources)
        parser.feed(markup)
        parser.close()
        return "".join(parser.parts), resources

    def test_approved_png_links_and_images_share_a_local_asset(self):
        source = self.images / "capture-settings.png"
        source.write_bytes(PNG)
        result, resources = self.parse('<a href="docs/images/capture-settings.png"><img src="docs/images/capture-settings.png" alt="Capture settings"></a>')
        self.assertEqual(result.count('="assets/screenshots/capture-settings.png"'), 2)
        self.assertIn('alt="Capture settings"', result)
        self.assertEqual(resources, {"assets/screenshots/capture-settings.png": source})

    def test_arbitrary_files_external_content_and_false_pngs_are_rejected(self):
        (self.images / "capture-settings.png").write_text("<html>not a PNG</html>")
        (self.images / "unreviewed.png").write_bytes(PNG)
        (self.root / "private.txt").write_text("private fixture")
        for target in ["docs/images/capture-settings.png", "docs/images/unreviewed.png", "private.txt",
                       "https://example.com/capture-settings.png", "data:image/png;base64,AAAA"]:
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.parse(f'<img src="{target}" alt="Example">')
        for markup in ['<script>alert(1)</script>', '<img src="docs/app-icon.png" onload="alert(1)">',
                       '<iframe src="docs/app-icon.png"></iframe>']:
            with self.subTest(markup=markup), self.assertRaises(ValueError):
                self.parse(markup)

    def test_screenshot_symlinks_cannot_copy_other_repository_files(self):
        other = self.root / "capture-settings.png"
        other.write_bytes(PNG)
        (self.images / "capture-settings.png").symlink_to(other)
        with self.assertRaises(ValueError):
            self.parse('<img src="docs/images/capture-settings.png" alt="Example">')

    def test_relative_links_validate_in_their_own_page_context(self):
        documents = {
            "index.html": '<a href="es/guide.html#captura">Español</a>',
            "es/guide.html": '<h2 id="captura">Captura</h2><a href="#captura">Aquí</a><a href="../index.html">English</a><img src="../assets/screenshots/history.png" alt="Historial">',
        }
        assets = {"assets/screenshots/history.png"}
        site.validate_local_links(documents, assets)
        for target in ["../../index.html", "../guide.html#missing", "/index.html", "%2e%2e/%2e%2e/index.html"]:
            with self.subTest(target=target), self.assertRaises(ValueError):
                site.validate_local_links({**documents, "es/guide.html": f'<a href="{target}">Broken</a>'}, assets)
        for resource in ["https://example.com/a.png", "../../assets/screenshots/history.png", "/assets/screenshots/history.png"]:
            with self.subTest(resource=resource), self.assertRaises(ValueError):
                site.validate_local_links({**documents, "es/guide.html": f'<img src="{resource}" alt="Unsafe">'}, assets)

    @unittest.skipUnless(shutil.which("pandoc"), "Pandoc is needed for the multilingual Markdown build")
    def test_languages_keep_current_page_share_images_and_translate_navigation(self):
        (self.images / "capture-settings.png").write_bytes(PNG)
        self.guide.write_text('# Guide\n\n<a id="capture"></a>\n\n## Capture\n')
        (self.root / "docs/PROVIDERS.md").write_text("# Providers\n")
        pages = dict(site.PAGES)
        for language in ["es", "it", "fr", "de"]:
            directory = self.root / "docs/locales" / language
            directory.mkdir(parents=True)
            localized = directory / "README.md"
            localized.write_text('# Smart Clipboard\n\n[Guide](../../USER-GUIDE.md#capture)\n\n[Provider details](../../PROVIDERS.md)\n\n[![Capture preferences](../../images/capture-settings.png)](../../images/capture-settings.png)\n\n*Choose your format.*\n')
            guide = directory / "USER-GUIDE.md"
            guide.write_text('# Guide\n\n<a id="capture"></a>\n\n## Capture\n\n[Home](../../../README.md)\n')
            pages[localized] = language + "/index.html"
            pages[guide] = language + "/guide.html"
        output = self.root / "multilingual"
        output.mkdir()
        (output / "appcast.xml").write_bytes(b"signed feed unchanged")
        arguments = [str(SCRIPT), "--ref", "v0.4.0-preview.15", "--output", str(output), "--omit-demo"]
        with patch.object(site, "PAGES", pages), patch.object(sys, "argv", arguments):
            site.main()
        self.assertEqual(len(list(output.rglob("*.html"))), 10)
        self.assertEqual(list((output / "assets/screenshots").iterdir()), [output / "assets/screenshots/capture-settings.png"])
        self.assertFalse(any((output / code / "assets").exists() for code in ["es", "it", "fr", "de"]))
        labels = {"es": "Descargas", "it": "Vai al contenuto", "fr": "Téléchargements", "de": "Zum Inhalt"}
        for language, label in labels.items():
            home = (output / language / "index.html").read_text()
            guide = (output / language / "guide.html").read_text()
            self.assertIn(f'<html lang="{language}">', home)
            self.assertIn(label, home)
            self.assertIn('href="guide.html#capture"', home)
            self.assertIn('href="index.html"', guide)
            self.assertIn('href="../assets/style.css"', home)
            self.assertIn('src="../assets/screenshots/capture-settings.png"', home)
            self.assertIn('href="../assets/screenshots/capture-settings.png"', home)
            self.assertIn('/blob/v0.4.0-preview.15/docs/PROVIDERS.md', home)
            self.assertIn('href="../guide.html" lang="en" hreflang="en"', guide)
            self.assertIn("default-src 'none'; style-src 'self'", home)
        spanish = (output / "es/guide.html").read_text()
        self.assertIn('href="../fr/guide.html" lang="fr" hreflang="fr"', spanish)
        self.assertIn('href="guide.html" lang="es" hreflang="es" aria-current="page"', spanish)
        self.assertIn('href="es/guide.html" lang="es" hreflang="es"', (output / "guide.html").read_text())
        self.assertEqual((output / "appcast.xml").read_bytes(), b"signed feed unchanged")
        manifest = json.loads((output / "help-build.json").read_text())
        self.assertEqual(manifest["languages"], ["en", "es", "it", "fr", "de"])
        self.assertEqual(len(manifest["screenshots"]), 1)
        self.assertIn("docs/locales/es/README.md", manifest["sources"])

    @unittest.skipUnless(shutil.which("pandoc"), "Pandoc is needed for the end-to-end Markdown build")
    def test_build_copies_only_referenced_screenshots_records_hashes_and_preserves_feed(self):
        (self.images / "capture-settings.png").write_bytes(PNG)
        (self.images / "history.png").write_bytes(PNG)
        self.readme.write_text("# Smart Clipboard\n\n[![Choose a capture format](docs/images/capture-settings.png)](docs/images/capture-settings.png)\n\n*Set it once, then capture without opening the app.*\n\n[Guide](docs/USER-GUIDE.md)\n")
        output = self.root / "staging"
        (output / "assets").mkdir(parents=True)
        (output / "appcast.xml").write_bytes(b"signed feed fixture")
        (output / "demo.mp4").write_bytes(b"existing recording fixture")
        (output / "assets/existing.png").write_bytes(PNG)
        arguments = [str(SCRIPT), "--ref", "v0.4.0-preview.13", "--output", str(output), "--omit-demo"]
        with patch.object(sys, "argv", arguments):
            site.main()
        copied = output / "assets/screenshots/capture-settings.png"
        self.assertEqual(copied.read_bytes(), PNG)
        self.assertFalse((output / "assets/screenshots/history.png").exists())
        self.assertEqual((output / "appcast.xml").read_bytes(), b"signed feed fixture")
        self.assertEqual((output / "demo.mp4").read_bytes(), b"existing recording fixture")
        self.assertEqual((output / "assets/existing.png").read_bytes(), PNG)
        content = (output / "index.html").read_text()
        self.assertIn('<figure class="screenshot">', content)
        self.assertIn('<figcaption>Set it once, then capture without opening the app.</figcaption>', content)
        self.assertIn('alt="Choose a capture format"', content)
        self.assertIn('href="assets/screenshots/capture-settings.png"', content)
        self.assertIn('src="assets/screenshots/capture-settings.png"', content)
        manifest = json.loads((output / "help-build.json").read_text())
        digest = hashlib.sha256(PNG).hexdigest()
        self.assertEqual(manifest["screenshots"], {"assets/screenshots/capture-settings.png": digest})
        self.assertEqual(manifest["sources"]["docs/images/capture-settings.png"], digest)
        self.assertNotIn("docs/images/history.png", manifest["sources"])


if __name__ == "__main__":
    unittest.main()
