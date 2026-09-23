#!/usr/bin/env python3
"""Verify locked dependency notices; --generate METADATA refreshes reviewed files."""
from pathlib import Path
from html.parser import HTMLParser
import argparse, hashlib, json, tomllib

ROOT = Path(__file__).resolve().parent
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--generate', type=Path, metavar='CARGO_METADATA_JSON')
args = parser.parse_args()
lock = tomllib.loads((ROOT / 'Cargo.lock').read_text())
packages = sorted((p['name'], p['version'], p.get('checksum')) for p in lock['package'] if p.get('source'))
notice = ROOT / 'THIRD_PARTY_NOTICES.txt'
manifest = ROOT / 'notices.json'
if args.generate:
    metadata = json.loads(args.generate.read_text())
    by_id = {(p['name'], p['version']): p for p in metadata['packages']}
    sections = ['SmartClipboardTrace dependency notices',
                'Pinned by Cargo.lock. Dual-license texts are included as supplied by each package.\n']
    records = []
    for name, version, checksum in packages:
        package = by_id[name, version]
        directory = Path(package['manifest_path']).parent
        licenses = [p for p in directory.iterdir() if p.is_file() and p.name.lower().startswith(('license', 'licence', 'copying', 'copyright', 'notice'))]
        if package.get('license_file'):
            licenses.append(directory / package['license_file'])
        if name == 'flo_curves' and version == '0.3.1' and not licenses:
            # Its published crate and recorded upstream commit omit a license
            # file, but Cargo.toml declares Apache-2.0; retain the standard text.
            assert package['license'] == 'Apache-2.0'
            licenses = [ROOT / 'licenses/Apache-2.0.txt']
        if name in ('winapi-i686-pc-windows-gnu', 'winapi-x86_64-pc-windows-gnu') and not licenses:
            licenses = [ROOT / 'licenses/winapi-LICENSE-MIT', ROOT / 'licenses/winapi-LICENSE-APACHE']
        licenses = sorted(set(licenses))
        if not licenses:
            raise SystemExit(f'Missing license text for {name} {version}; review the upstream package.')
        sections.append(f'\n{"=" * 72}\n{name} {version}\nLicense: {package.get("license", "See supplied text")}\nSource: {package.get("repository") or "https://crates.io/crates/" + name}\n')
        for file in licenses:
            sections.append(f'--- {file.name} ---\n{file.read_text()}\n')
        records.append({'name': name, 'version': version, 'checksum': checksum,
                        'license': package.get('license'), 'licenseFiles': [p.name for p in licenses]})
    class PlainText(HTMLParser):
        def __init__(self): super().__init__(); self.parts = []
        def handle_data(self, text): self.parts.append(text)
    runtime = PlainText()
    runtime.feed((ROOT / 'licenses/rust-1.94.0-library.html').read_text())
    sections.append('\n' + '=' * 72 + '\nRust 1.94.0 Standard Library\nSource: official Rust 1.94.0 toolchain, share/doc/rust/COPYRIGHT-library.html\n' + '\n'.join(runtime.parts))
    notice.write_text('\n'.join(sections))
    manifest.write_text(json.dumps({'lockSHA256': digest(ROOT / 'Cargo.lock'), 'noticesSHA256': digest(notice), 'rustLibraryNoticesSHA256': digest(ROOT / 'licenses/rust-1.94.0-library.html'), 'packages': records}, indent=2) + '\n')
record = json.loads(manifest.read_text())
assert record['lockSHA256'] == digest(ROOT / 'Cargo.lock'), 'Dependency lock changed: review and regenerate notices.'
assert record['noticesSHA256'] == digest(notice), 'Notice text changed without reviewed manifest.'
assert record['rustLibraryNoticesSHA256'] == digest(ROOT / 'licenses/rust-1.94.0-library.html')
assert [(p['name'], p['version'], p['checksum']) for p in record['packages']] == packages
print(f'Verified license notices for {len(packages)} locked dependencies.')
