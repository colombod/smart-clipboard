#!/usr/bin/env python3
"""Point a runner-only Xcode project at the separately built, isolated audit app."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys

source, app, destination = (Path(value).resolve() for value in sys.argv[1:4])
with (app / "Contents/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
if info.get("CFBundleIdentifier") != "com.smartclipboard.accessibility-audit":
    raise SystemExit("Refusing to target any app except com.smartclipboard.accessibility-audit.")
with source.open("rb") as handle:
    settings = plistlib.load(handle)


def resolve_test_root(value):
    if isinstance(value, str):
        return value.replace("__TESTROOT__", str(source.parent))
    if isinstance(value, list):
        return [resolve_test_root(item) for item in value]
    if isinstance(value, dict):
        return {key: resolve_test_root(item) for key, item in value.items()}
    return value


settings = resolve_test_root(settings)
targets = [target for configuration in settings.get("TestConfigurations", [])
           for target in configuration.get("TestTargets", [])]
if not targets:  # Xcode also supports the older single-configuration format.
    targets = [target for key, target in settings.items()
               if key != "__xctestrun_metadata__" and isinstance(target, dict) and "TestBundlePath" in target]
if len(targets) != 1 or targets[0].get("BlueprintName") != "AccessibilityAuditTests":
    raise SystemExit("Unexpected test-run structure; refusing to guess the target.")
target = targets[0]
target["UITargetAppPath"] = str(app)
target["UITargetAppBundleIdentifier"] = info["CFBundleIdentifier"]
target["ParallelizationEnabled"] = False
target["UserAttachmentLifetime"] = "keepAlways"
target.setdefault("EnvironmentVariables", {})["SMART_CLIPBOARD_AUDIT_APP_PATH"] = str(app)
products = target.setdefault("DependentProductPaths", [])
if str(app) not in products:
    products.append(str(app))
with destination.open("wb") as handle:
    plistlib.dump(settings, handle)
executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
(destination.parent / "audit-app.json").write_text(json.dumps({
    "path": str(app), "bundleIdentifier": info["CFBundleIdentifier"],
    "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
    "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(),
}, indent=2) + "\n")
