#!/usr/bin/env python3
"""Explicit local preparation, GitHub asset publication, then verified feed publication.

No private key input/export is supported. Sparkle tools use an existing Keychain
account; this program only receives public keys and signatures from them.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

REPO = pathlib.Path(__file__).resolve().parent.parent
GITHUB = 'colombod/smart-clipboard'
FEED = 'https://colombod.github.io/smart-clipboard/appcast.xml'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def fail(message):
    raise ValueError(message)


def run(*args, capture=True):
    environment = None
    if str(args[0]) == 'gh':
        environment = dict(os.environ, GH_HOST='github.com')
    return subprocess.run([str(a) for a in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None, env=environment).stdout


def sha(path):
    digest = hashlib.sha256()
    with pathlib.Path(path).open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def load(path):
    return json.loads(pathlib.Path(path).read_text())


def download(url, path, allow_missing=False):
    # Anonymous HTTPS only: no gh authentication is attached to asset downloads.
    result = run('curl', '--disable', '--silent', '--show-error', '--location', '--proto', '=https',
                 '--proto-redir', '=https', '--max-time', '180', '--output', path,
                 '--write-out', '%{http_code}', url).strip()
    if allow_missing and result == '404':
        pathlib.Path(path).unlink(missing_ok=True)
        return False
    if result != '200':
        fail(f'Public download returned HTTP {result}: {url}')
    return True


def numeric_build(value):
    if not re.fullmatch(r'[1-9][0-9]*', str(value)):
        fail('Release builds must be positive decimal integers.')
    return int(value)


def read_feed(path):
    data = pathlib.Path(path).read_bytes()
    if b'<!DOCTYPE' in data or b'<!ENTITY' in data:
        fail('Appcast DTD/entities are not supported.')
    root = ET.fromstring(data)
    channel = root.find('channel')
    if root.tag != 'rss' or channel is None:
        fail('Expected an RSS appcast with a channel.')
    return root, channel


def validate_new_build(channel, build):
    for item in channel.findall('item'):
        old = item.findtext(f'{{{NS}}}version')
        if old is None:
            old = item.find('enclosure').get(f'{{{NS}}}version') if item.find('enclosure') is not None else None
        if numeric_build(old) >= build:
            fail('Build must be greater than every published stable and preview build; never replace an existing build.')


def require_key(tools, account, expected):
    if len(base64.b64decode(expected, validate=True)) != 32:
        fail('SUPublicEDKey must contain a 32-byte Ed25519 public key.')
    actual = run(tools / 'generate_keys', '--account', account, '-p').strip()
    if actual != expected:
        fail('Keychain public key does not match the signed app SUPublicEDKey.')


def source_state():
    return run('git', '-C', REPO, 'rev-parse', 'HEAD').strip(), run('git', '-C', REPO, 'status', '--porcelain', '--untracked-files=normal')


def prepare(args):
    dist = REPO / 'dist'
    state = dist / 'notarization-release'
    app = dist / 'Smart Clipboard.app'
    if not (state / 'complete').is_file():
        fail('Complete signed/notarized release verification before preparing an update.')
    commit, dirty = source_state()
    provenance = load(dist / 'build-source.json')
    executable_hash = sha(app / 'Contents/MacOS/SmartClipboard')
    if dirty or provenance['dirty'] or provenance['commit'] != commit or provenance['executableSHA256'] != executable_hash:
        fail('Commit the reviewed source, then build/notarize that exact clean commit. The current build provenance does not match.')
    if (state / 'app.sha256').read_text().strip() != executable_hash:
        fail('Notarization state does not match the current app.')
    run('codesign', '--verify', '--deep', '--strict', app)
    run('xcrun', 'stapler', 'validate', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.smartclipboard.app' or info.get('SUFeedURL') != FEED:
        fail('Unexpected bundle identifier or update feed URL.')
    if info.get('SURequireSignedFeed') is not True:
        fail('The release must require signed update feeds.')
    if info.get('SUVerifyUpdateBeforeExtraction') is not True:
        fail('The release must verify updates before extraction.')
    version = info['CFBundleShortVersionString']
    build = numeric_build(info['CFBundleVersion'])
    if args.channel == 'preview':
        if args.tag != f'v{version}-preview.{build}':
            fail(f'Preview tag must be v{version}-preview.{build}.')
    elif args.tag != f'v{version}' or not args.approve_stable:
        fail('Stable publication requires its exact version tag and explicit --approve-stable after release acceptance.')
    if not re.fullmatch(r'[A-Za-z0-9._-]+', args.tag):
        fail('Invalid tag.')
    tools = args.sparkle_tools.resolve()
    require_key(tools, args.account, info.get('SUPublicEDKey', ''))
    output = dist / 'update-release'
    if output.exists():
        fail('dist/update-release already exists. Preserve/review it before preparing another release.')
    assets = []
    for line in (dist / 'SHA256SUMS.txt').read_text().splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  (Smart-Clipboard-[A-Za-z0-9._-]+\.(zip|dmg))', line)
        if not match or sha(dist / match[2]) != match[1]:
            fail('Release asset checksum mismatch or unsupported checksum entry.')
        assets.append({'name': match[2], 'sha256': match[1], 'length': (dist / match[2]).stat().st_size})
    if len(assets) != 2 or {pathlib.Path(a['name']).suffix for a in assets} != {'.zip', '.dmg'}:
        fail('Expected exactly one verified ZIP and DMG.')
    for asset in assets:
        if asset['name'] not in {f'Smart-Clipboard-{version}-macOS-arm64.zip', f'Smart-Clipboard-{version}-macOS-arm64.dmg'}:
            fail('Expected this app version and the supported arm64 release architecture.')
    zip_asset = next(a for a in assets if a['name'].endswith('.zip'))
    dmg_asset = next(a for a in assets if a['name'].endswith('.dmg'))
    if zip_asset['sha256'] != (state / 'zip.sha256').read_text().strip() or dmg_asset['sha256'] != (state / 'dmg-final.sha256').read_text().strip():
        fail('Assets differ from the completed notarization state.')
    with tempfile.TemporaryDirectory(prefix='smart-clipboard-feed-') as tmp:
        temp = pathlib.Path(tmp)
        previous = temp / 'previous.xml'
        exists = download(FEED, previous, allow_missing=True)
        if exists:
            if args.first_feed:
                fail('--first-feed cannot replace an existing feed.')
            run(tools / 'sign_update', '--account', args.account, '--verify', previous)
            root, channel = read_feed(previous)
            previous_hash = sha(previous)
        else:
            if not args.first_feed:
                fail('The public feed is missing. Use --first-feed only for the approved initial feed.')
            root = ET.Element('rss', {'version': '2.0'})
            channel = ET.SubElement(root, 'channel')
            ET.SubElement(channel, 'title').text = 'Smart Clipboard updates'
            ET.SubElement(channel, 'link').text = FEED
            ET.SubElement(channel, 'description').text = 'Signed Smart Clipboard releases'
            previous_hash = None
        validate_new_build(channel, build)
        signature = run(tools / 'sign_update', '--account', args.account, '-p', dist / zip_asset['name']).strip()
        if len(base64.b64decode(signature, validate=True)) != 64:
            fail('Sparkle did not return an Ed25519 signature.')
        run(tools / 'sign_update', '--account', args.account, '--verify', dist / zip_asset['name'], signature)
        item = ET.Element('item')
        ET.SubElement(item, 'title').text = f'Smart Clipboard {version}' + (' Preview' if args.channel == 'preview' else '')
        ET.SubElement(item, f'{{{NS}}}version').text = str(build)
        ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
        if args.channel == 'preview':
            ET.SubElement(item, f'{{{NS}}}channel').text = 'preview'
        ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
        ET.SubElement(item, f'{{{NS}}}hardwareRequirements').text = 'arm64'
        ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S %z')
        ET.SubElement(item, 'description', {f'{{{NS}}}format': 'plain-text'}).text = args.notes.read_text()
        ET.SubElement(item, 'enclosure', {'url': f'https://github.com/{GITHUB}/releases/download/{args.tag}/{zip_asset["name"]}',
                                        f'{{{NS}}}edSignature': signature, 'length': str(zip_asset['length']),
                                        'type': 'application/octet-stream'})
        channel.insert(0, item)
        feed = temp / 'appcast.xml'
        ET.ElementTree(root).write(feed, encoding='utf-8', xml_declaration=True)
        run(tools / 'sign_update', '--account', args.account, feed)
        run(tools / 'sign_update', '--account', args.account, '--verify', feed)
        output.mkdir()
        (output / 'appcast.xml').write_bytes(feed.read_bytes())
        (output / 'release-notes.txt').write_text(args.notes.read_text())
    assets.append({'name': 'SHA256SUMS.txt', 'sha256': sha(dist / 'SHA256SUMS.txt'), 'length': (dist / 'SHA256SUMS.txt').stat().st_size})
    manifest = {'repository': GITHUB, 'tag': args.tag, 'channel': args.channel, 'version': version, 'build': build,
                'commit': commit, 'appSHA256': executable_hash, 'feedURL': FEED,
                'feedSHA256': sha(output / 'appcast.xml'), 'previousFeedSHA256': previous_hash,
                'publicKey': info['SUPublicEDKey'], 'account': args.account, 'assets': assets,
                'notesSHA256': sha(output / 'release-notes.txt')}
    (output / 'release.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Prepared {output}. Review release.json, release-notes.txt and appcast.xml before publishing.')


def verify_local():
    output = REPO / 'dist/update-release'
    manifest = load(output / 'release.json')
    if manifest['repository'] != GITHUB or manifest['feedURL'] != FEED:
        fail('Unexpected publication target.')
    if sha(output / 'appcast.xml') != manifest['feedSHA256'] or sha(output / 'release-notes.txt') != manifest['notesSHA256']:
        fail('Prepared feed/notes changed; prepare and sign a new reviewed release.')
    for asset in manifest['assets']:
        if pathlib.Path(asset['name']).name != asset['name'] or sha(REPO / 'dist' / asset['name']) != asset['sha256']:
            fail('Prepared asset changed.')
    return output, manifest


def gh_json(*args):
    return json.loads(run('gh', *args))


def release_info(manifest):
    return gh_json('release', 'view', manifest['tag'], '--repo', GITHUB,
                   '--json', 'tagName,isDraft,isPrerelease,assets,targetCommitish')


def verify_release_identity(info, manifest):
    if info['tagName'] != manifest['tag'] or info['isPrerelease'] != (manifest['channel'] == 'preview'):
        fail('GitHub release tag/channel differs from the reviewed manifest.')
    # A public tag must already exist, and resolve to the exact built commit.
    refs = run('git', 'ls-remote', '--tags', f'https://github.com/{GITHUB}.git',
               f'refs/tags/{manifest["tag"]}', f'refs/tags/{manifest["tag"]}^{{}}').splitlines()
    resolved = {ref: commit for commit, ref in (line.split('\t') for line in refs)}
    expected_ref = f'refs/tags/{manifest["tag"]}'
    if resolved.get(expected_ref + '^{}', resolved.get(expected_ref)) != manifest['commit']:
        fail('Public release tag does not resolve to the exact reviewed build commit.')


def verify_public(manifest):
    info = release_info(manifest)
    verify_release_identity(info, manifest)
    if info['isDraft']:
        fail('Release is still a draft; the feed cannot be published.')
    with tempfile.TemporaryDirectory(prefix='smart-clipboard-public-') as tmp:
        for asset in manifest['assets']:
            path = pathlib.Path(tmp) / asset['name']
            download(f'https://github.com/{GITHUB}/releases/download/{manifest["tag"]}/{asset["name"]}', path)
            if sha(path) != asset['sha256'] or path.stat().st_size != asset['length']:
                fail(f'Public asset does not match reviewed bytes: {asset["name"]}')


def publish_release(args):
    output, manifest = verify_local()
    if args.approve_tag != manifest['tag']:
        fail('--approve-tag must exactly name the reviewed release.')
    if gh_json('repo', 'view', GITHUB, '--json', 'visibility')['visibility'] != 'PUBLIC':
        fail('Update repository must be public before release publication.')
    # Check remote tag before any write. Do not create tags or silently move them.
    verify_release_identity({'tagName': manifest['tag'], 'isPrerelease': manifest['channel'] == 'preview'}, manifest)
    # An HTTP 404 is the only absent-release condition; auth/network errors stop.
    releases = gh_json('api', '--paginate', '--slurp', f'repos/{GITHUB}/releases?per_page=100')
    matching = [r for page in releases for r in page if r['tag_name'] == manifest['tag']]
    if not matching:
        command = ['gh', 'release', 'create', manifest['tag'], '--repo', GITHUB, '--draft', '--verify-tag',
                   '--title', f'Smart Clipboard {manifest["version"]}' + (' Preview' if manifest['channel'] == 'preview' else ''),
                   '--notes-file', output / 'release-notes.txt']
        if manifest['channel'] == 'preview': command.append('--prerelease')
        run(*command)
    info = release_info(manifest)
    verify_release_identity(info, manifest)
    if info['isDraft']:
        names = {a['name'] for a in info['assets']}
        with tempfile.TemporaryDirectory(prefix='smart-clipboard-draft-') as tmp:
            for asset in manifest['assets']:
                if asset['name'] in names:
                    run('gh', 'release', 'download', manifest['tag'], '--repo', GITHUB, '--pattern', asset['name'], '--dir', tmp)
                    if sha(pathlib.Path(tmp) / asset['name']) != asset['sha256']:
                        fail('Draft asset differs; refusing to overwrite it.')
                else:
                    run('gh', 'release', 'upload', manifest['tag'], REPO / 'dist' / asset['name'], '--repo', GITHUB)
        run('gh', 'release', 'edit', manifest['tag'], '--repo', GITHUB, '--draft=false',
            '--latest=false' if manifest['channel'] == 'preview' else '--latest=true')
    verify_public(manifest)
    print('Release is public and every asset matches. Feed has not been published.')


def publish_feed(args):
    output, manifest = verify_local()
    if args.approve_tag != manifest['tag']:
        fail('--approve-tag must exactly name the reviewed release.')
    verify_public(manifest)  # Always re-download; a prior receipt is insufficient.
    tools = args.sparkle_tools.resolve()
    require_key(tools, manifest['account'], manifest['publicKey'])
    run(tools / 'sign_update', '--account', manifest['account'], '--verify', output / 'appcast.xml')
    pages = gh_json('api', f'repos/{GITHUB}/pages')
    if pages.get('source') != {'branch': 'gh-pages', 'path': '/'} or pages.get('html_url') != FEED.removesuffix('appcast.xml'):
        fail('Approve/configure GitHub Pages from gh-pages root at the expected URL first.')
    with tempfile.TemporaryDirectory(prefix='smart-clipboard-pages-') as tmp:
        current = pathlib.Path(tmp) / 'current.xml'
        exists = download(FEED, current, allow_missing=True)
        current_hash = sha(current) if exists else None
        if current_hash == manifest['feedSHA256']:
            print('The exact signed feed is already public.'); return
        if current_hash != manifest['previousFeedSHA256']:
            fail('Published feed changed since preparation; refusing stale overwrite.')
        # Compare the branch as well as the served feed, protecting in-flight Pages deployments.
        tree = gh_json('api', f'repos/{GITHUB}/git/trees/gh-pages')
        entry = next((e for e in tree['tree'] if e['path'] == 'appcast.xml'), None)
        payload = {'message': f'Publish verified {manifest["tag"]} update feed', 'branch': 'gh-pages',
                   'content': base64.b64encode((output / 'appcast.xml').read_bytes()).decode()}
        if entry:
            blob = gh_json('api', f'repos/{GITHUB}/git/blobs/{entry["sha"]}')
            data = base64.b64decode(blob['content'])
            branch_hash = hashlib.sha256(data).hexdigest()
            if branch_hash == manifest['feedSHA256']:
                print('The exact signed feed is already committed. Run verify-feed after Pages deployment.'); return
            if branch_hash != manifest['previousFeedSHA256']:
                fail('Feed branch differs from the prepared base; refusing stale overwrite.')
            payload['sha'] = entry['sha']
        elif manifest['previousFeedSHA256'] is not None:
            fail('Published feed is missing from the configured Pages branch.')
        request = pathlib.Path(tmp) / 'request.json'
        request.write_text(json.dumps(payload))
        run('gh', 'api', '--method', 'PUT', f'repos/{GITHUB}/contents/appcast.xml', '--input', request)
    print('Signed feed committed to gh-pages. Pages deployment is asynchronous; verify the public feed before claiming availability.')


def verify_feed(args):
    _, manifest = verify_local()
    verify_public(manifest)
    tools = args.sparkle_tools.resolve()
    require_key(tools, manifest['account'], manifest['publicKey'])
    with tempfile.TemporaryDirectory(prefix='smart-clipboard-feed-check-') as tmp:
        feed = pathlib.Path(tmp) / 'appcast.xml'
        download(FEED, feed)
        if sha(feed) != manifest['feedSHA256']:
            fail('Public feed does not yet match the reviewed signed feed; inspect Pages deployment.')
        run(tools / 'sign_update', '--account', manifest['account'], '--verify', feed)
    print('Public signed feed and all release downloads verified. Live updater acceptance remains a separate test.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    prep = actions.add_parser('prepare')
    prep.add_argument('--tag', required=True)
    prep.add_argument('--channel', choices=['preview', 'stable'], required=True)
    prep.add_argument('--notes', type=pathlib.Path, required=True)
    prep.add_argument('--sparkle-tools', type=pathlib.Path, required=True)
    prep.add_argument('--account', default='smart-clipboard')
    prep.add_argument('--first-feed', action='store_true')
    prep.add_argument('--approve-stable', action='store_true')
    prep.set_defaults(function=prepare)
    for name, function in [('publish-release', publish_release), ('publish-feed', publish_feed)]:
        command = actions.add_parser(name)
        command.add_argument('--approve-tag', required=True)
        if name == 'publish-feed': command.add_argument('--sparkle-tools', type=pathlib.Path, required=True)
        command.set_defaults(function=function)
    check = actions.add_parser('verify-public')
    check.set_defaults(function=lambda _: (verify_public(verify_local()[1]), print('Public release assets verified.')))
    feed_check = actions.add_parser('verify-feed')
    feed_check.add_argument('--sparkle-tools', type=pathlib.Path, required=True)
    feed_check.set_defaults(function=verify_feed)
    args = parser.parse_args()
    try:
        args.function(args)
    except (ValueError, OSError, KeyError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Error: {error}\n')


if __name__ == '__main__':
    main()
