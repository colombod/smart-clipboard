#!/usr/bin/env python3
"""Reject incomplete native audit runs using xcresulttool's structured exports.

The field names and node/result enums below follow Xcode 27's local
`xcresulttool get test-results {summary,tests} --schema`. Missing identities,
unknown result/node types, and unsupported source declarations fail closed.
"""
import argparse
import json
from pathlib import Path
import re
import sys


TARGET = "AccessibilityAuditTests"
NODE_TYPES = {
    "Test Plan", "Unit test bundle", "UI test bundle", "Test Suite", "Test Case",
    "Device", "Test Plan Configuration", "Arguments", "Repetition", "Test Case Run",
    "Failure Message", "Source Code Reference", "Attachment", "Expression", "Test Value",
    "Runtime Warning", "Skip Message", "Expected Failure",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def expected_tests(source, selection):
    # These fixtures deliberately use one class and zero-argument XCTest methods.
    # Reject a new declaration style rather than silently omit it from coverage.
    classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source)
    require(classes == [TARGET], "Expected exactly the AccessibilityAuditTests XCTestCase class.")
    declared = re.findall(r"\bfunc\s+(test\w*)\s*\(", source)
    supported = re.findall(r"@MainActor\s+func\s+(test\w*)\s*\(\s*\)", source)
    require(declared and declared == supported and len(set(declared)) == len(declared),
            "Unknown, duplicate, or empty native test declaration list.")
    expected = {TARGET + "/" + name for name in declared}
    if selection:
        require(selection in expected, "Unknown --only-testing selection: " + selection)
        return {selection}
    return expected


def test_method(value):
    require(isinstance(value, str), "Test Case name is missing or not a string.")
    match = re.fullmatch(r"(test\w*)(?:\(\))?", value)
    require(match is not None, "Unknown Test Case name format: " + value)
    return match.group(1)


def verify(summary, tests, expected):
    require(isinstance(summary, dict) and isinstance(tests, dict), "Unknown xcresult export shape.")
    require(summary.get("result") == "Passed", "The native test summary is not Passed.")
    counts = {"totalTestCount": len(expected), "passedTests": len(expected),
              "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    for key, wanted in counts.items():
        require(type(summary.get(key)) is int and summary[key] == wanted,
                f"Expected {key}={wanted}; got {summary.get(key)!r}.")
    require(summary.get("testFailures") == [], "Summary testFailures must be an empty array.")
    for key in ("testPlanConfigurations", "devices", "testNodes"):
        require(isinstance(tests.get(key), list), "Unknown tests schema: missing array " + key)
    require(tests["testNodes"], "No native test nodes were exported.")

    actual = set()

    def visit(node, bundle=None, suite=None, in_case=False):
        require(isinstance(node, dict), "Unknown test node shape.")
        kind, name = node.get("nodeType"), node.get("name")
        require(kind in NODE_TYPES and isinstance(name, str), "Unknown test node type/name.")
        if "result" in node:
            require(node["result"] == "Passed", f"Non-passing node {name}: {node['result']!r}.")
        require(kind not in {"Failure Message", "Skip Message", "Expected Failure"},
                "Failure/skip detail present: " + name)
        if kind in {"UI test bundle", "Unit test bundle"}:
            require(kind == "UI test bundle" and name in {TARGET, TARGET + ".xctest"},
                    "Unexpected test bundle: " + name)
            bundle = TARGET
        elif kind == "Test Suite":
            suite = name
        elif kind == "Test Case":
            require(not in_case and bundle == TARGET, "Test Case is outside the expected UI test bundle.")
            require(suite is None or suite in {TARGET, TARGET + "." + TARGET},
                    "Unexpected Test Case suite: " + str(suite))
            require(node.get("result") == "Passed", "Test Case has no successful result: " + name)
            method = test_method(name)
            identity = TARGET + "/" + method
            identifier = node.get("nodeIdentifier")
            if identifier is not None:
                accepted = {identity, identity + "()", TARGET + "/" + identity, TARGET + "/" + identity + "()"}
                require(identifier in accepted, "Unknown or mismatched Test Case identifier: " + str(identifier))
            else:
                require(suite in {TARGET, TARGET + "." + TARGET},
                        "Test Case has neither an exact identifier nor the expected suite.")
            require(identity not in actual, "Duplicate Test Case: " + identity)
            actual.add(identity)
            in_case = True
        elif kind == "Test Case Run":
            require(in_case and node.get("result") == "Passed", "Incomplete or misplaced Test Case Run.")
        children = node.get("children", [])
        require(isinstance(children, list), "Unknown children shape for " + name)
        for child in children:
            visit(child, bundle, suite, in_case)

    for node in tests["testNodes"]:
        visit(node)
    require(actual == expected,
            "Native test selection mismatch. Missing: " + ", ".join(sorted(expected - actual))
            + "; unexpected: " + ", ".join(sorted(actual - expected)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("tests", type=Path)
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("AccessibilityAuditTests.swift"))
    parser.add_argument("--only-testing", default="")
    args = parser.parse_args()
    try:
        expected = expected_tests(args.source.read_text(), args.only_testing)
        verify(json.loads(args.summary.read_text()), json.loads(args.tests.read_text()), expected)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print("Native audit execution was not verified: " + str(error), file=sys.stderr)
        return 1
    print(f"Verified {len(expected)} selected native test(s): all executed and passed, with no skips.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
