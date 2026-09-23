import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("localizations", Path(__file__).resolve().parents[2] / "scripts/check-localizations.py")
LOCALIZATIONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LOCALIZATIONS)


class LocalizationCatalogTests(unittest.TestCase):
    def test_nested_expressions_and_localized_arguments(self):
        source = r'''L10n.text("Saved \(name) as \(flag ? L10n.text("Plain text") : L10n.text("Image")).")'''
        self.assertEqual(LOCALIZATIONS.extract_keys(source), {"Saved %1$@ as %2$@.", "Plain text", "Image"})

    def test_comments_and_nonlocalized_strings_are_not_keys(self):
        source = r'''// L10n.text("Comment")
        /* nested /* L10n.text("Comment") */ comment */
        let example = "L10n.text(\"Example\")"
        let prompt = "Preserve the source language"
        let text = L10n.text("Actual key")
        '''
        self.assertEqual(LOCALIZATIONS.extract_keys(source), {"Actual key"})

    def test_nested_parentheses_comments_and_escaped_quotes(self):
        source = r'''L10n.text("Result: \(f((1 + 2), "a)\"b", /* ) */ g(3)))")'''
        self.assertEqual(LOCALIZATIONS.extract_keys(source), {"Result: %1$@"})

    def test_swift_escapes_and_raw_strings(self):
        source = r'''L10n.text("Line\n\u{1F4CB} \"quoted\""); L10n.text(#"Literal \n; value \#(value)"#)'''
        self.assertEqual(LOCALIZATIONS.extract_keys(source), {'Line\n📋 "quoted"', r"Literal \n; value %1$@"})

    def test_multiline_indentation(self):
        source = 'L10n.text("""\n    First line\n      Indented line\n    Last \\(name)\n    """)'
        self.assertEqual(LOCALIZATIONS.extract_keys(source), {"First line\n  Indented line\nLast %1$@"})

    def test_runtime_lookup_and_concatenation_require_explicit_keys(self):
        for source in ['L10n.text(userContent)', 'L10n.key(userContent)', 'L10n.text("Prefix" + name)']:
            with self.subTest(source=source), self.assertRaises(LOCALIZATIONS.CatalogError):
                LOCALIZATIONS.extract_keys(source)

    def test_duplicate_keys_are_not_silently_overwritten(self):
        with self.assertRaisesRegex(LOCALIZATIONS.CatalogError, "Duplicate key"):
            LOCALIZATIONS.parse_catalog('"Ready" = "First"; /* comment */ "Ready" = "Second";')

    def test_catalog_escapes(self):
        self.assertEqual(LOCALIZATIONS.parse_catalog(r'''"a\"b" = "line\nnext";'''), {'a"b': 'line\nnext'})

    def test_placeholder_counts_and_catalog_coverage(self):
        key = "Saved %1$@ in %2$@."
        self.assertEqual(LOCALIZATIONS.validate_catalog({key: "In %2$@: %1$@."}, {key}), [])
        self.assertTrue(LOCALIZATIONS.validate_catalog({key: "In %2$@: %2$@."}, {key}))
        self.assertTrue(LOCALIZATIONS.validate_catalog({key: ""}, {key}))
        self.assertTrue(LOCALIZATIONS.validate_catalog({}, {key}))
        self.assertTrue(LOCALIZATIONS.validate_catalog({key: key, "Other": "Other"}, {key}))
        self.assertTrue(LOCALIZATIONS.validate_catalog({key: key + " %@"}, {key}))

    def test_packaged_binary_strings_are_checked(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "Localizable.strings"
            path.write_bytes(plistlib.dumps({"Ready": "Pronto"}, fmt=plistlib.FMT_BINARY))
            self.assertEqual(LOCALIZATIONS.packaged_catalog(path), {"Ready": "Pronto"})

    def test_packaged_app_detects_missing_or_stale_resources(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            app = root / "Smart Clipboard.app"
            resources = app / "Contents/Resources"
            bundle_resources = resources / "SmartClipboard_ClipboardCore.bundle/Contents/Resources"
            resources.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleLocalizations": list(LOCALIZATIONS.LANGUAGES), "CFBundleDevelopmentRegion": "en"
            }))
            for language in LOCALIZATIONS.LANGUAGES:
                for source, packaged in [
                    (root / f"Sources/ClipboardCore/Resources/{language}.lproj/Localizable.strings", bundle_resources / f"{language}.lproj/Localizable.strings"),
                    (root / f"Resources/{language}.lproj/InfoPlist.strings", resources / f"{language}.lproj/InfoPlist.strings"),
                ]:
                    source.parent.mkdir(parents=True)
                    source.write_text('"Ready" = "Translated";\n')
                    packaged.parent.mkdir(parents=True)
                    packaged.write_bytes(plistlib.dumps({"Ready": "Translated"}, fmt=plistlib.FMT_BINARY))
            self.assertEqual(LOCALIZATIONS.check_app(root, app), [])
            broken = bundle_resources / "de.lproj/Localizable.strings"
            broken.write_bytes(plistlib.dumps({"Ready": "Old translation"}, fmt=plistlib.FMT_BINARY))
            self.assertTrue(any("differ from" in error for error in LOCALIZATIONS.check_app(root, app)))
            broken.unlink()
            self.assertTrue(any("missing or invalid" in error for error in LOCALIZATIONS.check_app(root, app)))


if __name__ == "__main__":
    unittest.main()
