#!/usr/bin/env python3
"""Compare bundle contents and permissions without following framework links."""
import hashlib
import os
from pathlib import Path
import stat
import sys


def manifest(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f'Expected a real bundle directory: {root}')
    entries = {}

    def visit(directory):
        with os.scandir(directory) as children:
            for child in children:
                path = Path(child.path)
                name = path.relative_to(root).as_posix()
                metadata = child.stat(follow_symlinks=False)
                mode = stat.S_IMODE(metadata.st_mode)
                if stat.S_ISLNK(metadata.st_mode):
                    entries[name] = ('link', os.readlink(path))
                elif stat.S_ISDIR(metadata.st_mode):
                    entries[name] = ('directory', mode)
                    visit(path)
                elif stat.S_ISREG(metadata.st_mode):
                    digest = hashlib.sha256()
                    with path.open('rb') as stream:
                        for block in iter(lambda: stream.read(1024 * 1024), b''):
                            digest.update(block)
                    entries[name] = ('file', mode, metadata.st_size, digest.hexdigest())
                else:
                    raise ValueError(f'Unsupported bundle entry: {name}')

    visit(root)
    return entries


def compare(left, right):
    before, after = manifest(left), manifest(right)
    differences = [name for name in sorted(before.keys() | after.keys())
                   if before.get(name) != after.get(name)]
    if differences:
        raise ValueError('Bundle entries differ: ' + ', '.join(differences))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('Usage: compare-bundles.py ORIGINAL COPY')
    try:
        compare(*sys.argv[1:])
    except (OSError, ValueError) as error:
        sys.exit(str(error))
