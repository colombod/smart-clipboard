#!/usr/bin/env python3
"""Extract explicit UI keys and validate complete, structurally safe translations.

Run --write-english after adding L10n.text calls, then translate the resulting
catalog. Ordinary strings, prompts, protocol values and captured content are
never catalog inputs. This checker does not assess translation quality.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "it", "es", "fr", "de")
TOKEN = re.compile(r"%([1-9][0-9]*)\$@")
FORMAT_TOKEN = re.compile(r"%(?:[0-9]+\$)?[@a-zA-Z]")
CALL = re.compile(r"L10n\.(text|key)\b")


class CatalogError(ValueError):
    pass


def trivia(source: str, at: int) -> int:
    while at < len(source):
        if source[at].isspace():
            at += 1
        elif source.startswith("//", at):
            end = source.find("\n", at + 2)
            at = len(source) if end < 0 else end + 1
        elif source.startswith("/*", at):
            at += 2
            depth = 1
            while depth and at < len(source):
                if source.startswith("/*", at):
                    depth += 1
                    at += 2
                elif source.startswith("*/", at):
                    depth -= 1
                    at += 2
                else:
                    at += 1
            if depth:
                raise CatalogError("Unterminated block comment")
        else:
            break
    return at


def string_start(source: str, at: int) -> bool:
    return re.match(r'#*"', source[at:]) is not None


def interpolation_end(source: str, at: int) -> int:
    """Return the matching ')', skipping nested literals and comments."""
    depth = 1
    while at < len(source):
        after_trivia = trivia(source, at)
        if after_trivia != at:
            at = after_trivia
            continue
        if string_start(source, at):
            _, at, _ = swift_string(source, at)
        elif source[at] == "(":
            depth += 1
            at += 1
        elif source[at] == ")":
            depth -= 1
            if depth == 0:
                return at
            at += 1
        else:
            at += 1
    raise CatalogError("Unterminated Swift interpolation")


def swift_string(source: str, at: int) -> tuple[str, int, list[str]]:
    """Decode a Swift literal into the key built by L10n.Message."""
    start = at
    while source[at] == "#":
        at += 1
    hashes = source[start:at]
    quote = '"""' if source.startswith('"""', at) else '"'
    at += len(quote)
    closing = quote + hashes
    escape = "\\" + hashes
    chunks: list[str] = []
    expressions: list[str] = []
    while at < len(source):
        if source.startswith(closing, at):
            value = "".join(chunks)
            if len(quote) == 3:
                indent = source[source.rfind("\n", 0, at) + 1:at]
                if indent.strip():
                    raise CatalogError("Multiline closing delimiter must be on its own line")
                if value.startswith("\r\n"):
                    value = value[2:]
                elif value.startswith("\n"):
                    value = value[1:]
                else:
                    raise CatalogError("Multiline literal must start with a newline")
                if indent:
                    value = value[:-len(indent)]
                if value.endswith("\r\n"):
                    value = value[:-2]
                elif value.endswith("\n"):
                    value = value[:-1]
                lines = value.split("\n")
                if any(line.strip() and not line.startswith(indent) for line in lines):
                    raise CatalogError("Invalid multiline literal indentation")
                value = "\n".join(line[len(indent):] if line.startswith(indent) else "" for line in lines)
            return value, at + len(closing), expressions
        if source.startswith(escape, at):
            code_at = at + len(escape)
            if code_at >= len(source):
                raise CatalogError("Unterminated string escape")
            code = source[code_at]
            if code == "(":
                end = interpolation_end(source, code_at + 1)
                expressions.append(source[code_at + 1:end])
                chunks.append(f"%{len(expressions)}$@")
                at = end + 1
                continue
            escapes = {"0": "\0", "t": "\t", "n": "\n", "r": "\r", '"': '"', "'": "'", "\\": "\\"}
            if code in escapes:
                chunks.append(escapes[code])
                at = code_at + 1
                continue
            if code == "u" and source.startswith("{", code_at + 1):
                end = source.find("}", code_at + 2)
                if end < 0:
                    raise CatalogError("Unterminated Unicode escape")
                chunks.append(chr(int(source[code_at + 2:end], 16)))
                at = end + 1
                continue
            if code in "\r\n" and len(quote) == 3:
                at = code_at
                while at < len(source) and source[at].isspace():
                    at += 1
                continue
            raise CatalogError(f"Unsupported Swift escape: {source[at:code_at + 1]!r}")
        chunks.append(source[at])
        at += 1
    raise CatalogError("Unterminated Swift string")


def extract_keys(source: str) -> set[str]:
    keys: set[str] = set()
    at = 0
    while at < len(source):
        after_trivia = trivia(source, at)
        if after_trivia != at:
            at = after_trivia
            continue
        call = CALL.match(source, at)
        if call and (at == 0 or not (source[at - 1].isalnum() or source[at - 1] == "_")):
            opening = trivia(source, call.end())
            if opening >= len(source) or source[opening] != "(":
                at = call.end()
                continue
            literal = trivia(source, opening + 1)
            if not string_start(source, literal):
                line = source.count("\n", 0, at) + 1
                raise CatalogError(f"Line {line}: {call.group()} needs an explicit catalog literal")
            value, at, expressions = swift_string(source, literal)
            following = trivia(source, at)
            if following >= len(source) or source[following] not in ",)":
                raise CatalogError(f"Use one literal, not an expression, in {call.group()}")
            if call.group(1) == "key" and expressions:
                raise CatalogError("L10n.key must not interpolate user content")
            keys.add(value)
            for expression in expressions:
                keys.update(extract_keys(expression))
        elif string_start(source, at):
            _, at, expressions = swift_string(source, at)
            for expression in expressions:
                keys.update(extract_keys(expression))
        else:
            at += 1
    return keys


def collect_keys(root: Path) -> set[str]:
    keys: set[str] = set()
    for path in sorted((root / "Sources").rglob("*.swift")):
        try:
            keys.update(extract_keys(path.read_text()))
        except (CatalogError, ValueError) as error:
            raise CatalogError(f"{path.relative_to(root)}: {error}") from error
    return keys


def quoted_string(source: str, at: int) -> tuple[str, int]:
    if at >= len(source) or source[at] != '"':
        raise CatalogError("Catalog keys and values must use quoted strings")
    at += 1
    result: list[str] = []
    while at < len(source):
        if source[at] == '"':
            return "".join(result), at + 1
        if source[at] != "\\":
            result.append(source[at])
            at += 1
            continue
        at += 1
        if at >= len(source):
            break
        code = source[at]
        simple = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", '"': '"', "\\": "\\"}
        if code in simple:
            result.append(simple[code])
            at += 1
        elif code in "uU" and re.fullmatch(r"[0-9A-Fa-f]{4}", source[at + 1:at + 5]):
            result.append(chr(int(source[at + 1:at + 5], 16)))
            at += 5
        elif code in "01234567":
            match = re.match(r"[0-7]{1,3}", source[at:])
            assert match
            result.append(chr(int(match.group(), 8)))
            at += len(match.group())
        else:
            raise CatalogError(f"Unsupported catalog escape: \\{code}")
    raise CatalogError("Unterminated catalog string")


def parse_catalog(source: str) -> dict[str, str]:
    values: dict[str, str] = {}
    at = trivia(source.lstrip("\ufeff"), 0)
    source = source.lstrip("\ufeff")
    while at < len(source):
        key, at = quoted_string(source, at)
        at = trivia(source, at)
        if at >= len(source) or source[at] != "=":
            raise CatalogError(f"Missing '=' after {key!r}")
        value, at = quoted_string(source, trivia(source, at + 1))
        at = trivia(source, at)
        if at >= len(source) or source[at] != ";":
            raise CatalogError(f"Missing ';' after {key!r}")
        if key in values:
            raise CatalogError(f"Duplicate key: {key!r}")
        values[key] = value
        at = trivia(source, at + 1)
    return values


def read_catalog(path: Path) -> dict[str, str]:
    try:
        values = parse_catalog(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, CatalogError) as error:
        raise CatalogError(f"{path}: {error}") from error
    # Apple's parser is the authority for the files shipped in the app. The
    # separate lexical pass above preserves duplicates that plutil would lose.
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise CatalogError(f"{path}: invalid Apple strings file: {result.stderr or result.stdout}")
    if json.loads(result.stdout) != values:
        raise CatalogError(f"{path}: catalog decoding differs from Apple's strings parser")
    return values


def validate_catalog(values: dict[str, str], expected: set[str]) -> list[str]:
    failures: list[str] = []
    missing = expected - values.keys()
    extra = values.keys() - expected
    if missing:
        failures.append(f"Missing {len(missing)} keys: {sorted(missing)!r}")
    if extra:
        failures.append(f"Unexpected {len(extra)} keys: {sorted(extra)!r}")
    for key, value in values.items():
        if not value.strip():
            failures.append(f"Empty translation: {key!r}")
        if Counter(TOKEN.findall(key)) != Counter(TOKEN.findall(value)):
            failures.append(f"Placeholder mismatch: {key!r} -> {value!r}")
        elif Counter(FORMAT_TOKEN.findall(key)) != Counter(FORMAT_TOKEN.findall(value)):
            failures.append(f"Unexpected format token: {key!r} -> {value!r}")
    return failures


def write_english(root: Path, keys: set[str]) -> None:
    path = root / "Sources/ClipboardCore/Resources/en.lproj/Localizable.strings"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["/* Generated from explicit L10n calls. Preserve positional %1$@ tokens in translations. */"]
    lines.extend(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(key, ensure_ascii=False)};" for key in sorted(keys))
    path.write_text("\n".join(lines) + "\n")


def check(root: Path, keys: set[str]) -> list[str]:
    errors: list[str] = []
    info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
    permission_keys = {key for key, value in info.items() if key.endswith("UsageDescription") and isinstance(value, str)}
    if set(info.get("CFBundleLocalizations", [])) != set(LANGUAGES):
        errors.append("Info.plist CFBundleLocalizations must match supported catalog languages")
    if info.get("CFBundleDevelopmentRegion") != "en":
        errors.append("Info.plist must use English as the development region")
    for language in LANGUAGES:
        for path, expected in [
            (root / f"Sources/ClipboardCore/Resources/{language}.lproj/Localizable.strings", keys),
            (root / f"Resources/{language}.lproj/InfoPlist.strings", permission_keys),
        ]:
            try:
                values = read_catalog(path)
                errors.extend(f"{path.relative_to(root)}: {failure}" for failure in validate_catalog(values, expected))
                if language == "en":
                    expected_values = info if path.name == "InfoPlist.strings" else {key: key for key in keys}
                    errors.extend(f"{path.relative_to(root)}: English source mismatch: {key!r}"
                                  for key, value in values.items() if key in expected_values and value != expected_values[key])
            except CatalogError as error:
                errors.append(str(error))
    return errors


def packaged_catalog(path: Path) -> dict[str, str]:
    # Xcode may compile .strings into binary property lists. Compare parsed
    # contents with the reviewed source, not their on-disk representation.
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise CatalogError(f"{path}: missing or invalid packaged catalog")
    values = json.loads(result.stdout)
    if not isinstance(values, dict) or any(not isinstance(value, str) for value in values.values()):
        raise CatalogError(f"{path}: packaged catalog is not a string dictionary")
    return values


def check_app(root: Path, app: Path) -> list[str]:
    errors: list[str] = []
    resources = app / "Contents/Resources"
    bundle = resources / "SmartClipboard_ClipboardCore.bundle"
    bundle_resources = bundle / "Contents/Resources" if (bundle / "Contents/Resources").is_dir() else bundle
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if set(info.get("CFBundleLocalizations", [])) != set(LANGUAGES) or info.get("CFBundleDevelopmentRegion") != "en":
            errors.append("Packaged app does not declare all supported languages and English fallback")
    except (OSError, ValueError) as error:
        errors.append(f"Could not read packaged app Info.plist: {error}")
    for language in LANGUAGES:
        for source, packaged in [
            (root / f"Sources/ClipboardCore/Resources/{language}.lproj/Localizable.strings", bundle_resources / f"{language}.lproj/Localizable.strings"),
            (root / f"Resources/{language}.lproj/InfoPlist.strings", resources / f"{language}.lproj/InfoPlist.strings"),
        ]:
            try:
                if packaged_catalog(packaged) != read_catalog(source):
                    errors.append(f"{packaged}: packaged translations differ from the reviewed source")
            except CatalogError as error:
                errors.append(str(error))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write-english", action="store_true", help="Rewrite only the English UI catalog from explicit source keys")
    mode.add_argument("--app", type=Path, help="Also verify translation resources in an assembled app against the source catalogs")
    args = parser.parse_args()
    try:
        keys = collect_keys(ROOT)
        if args.write_english:
            write_english(ROOT, keys)
            print(f"Wrote {len(keys)} English UI keys. Other languages were not modified.")
            return 0
        errors = check(ROOT, keys)
        if args.app:
            errors.extend(check_app(ROOT, args.app))
    except (OSError, ValueError, CatalogError) as error:
        print(error, file=sys.stderr)
        return 1
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Validated {len(keys)} UI keys and permission strings in {len(LANGUAGES)} languages" + (f", including {args.app}." if args.app else "."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
