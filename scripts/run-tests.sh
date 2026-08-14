#!/bin/bash
# Runs the UpdatePolicy unit tests (spec S-0001 §8.6 T-2/T-5).
#
# Compiles src/UpdatePolicy.swift + tests/UpdatePolicyTests.swift into a CLI
# test runner and executes it. Exits non-zero on any assertion failure, so CI
# and local development can treat it as a gate.
#
# Usage (from the repo root):
#   ./scripts/run-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BIN="$(mktemp -d)/UpdatePolicyTests"
trap 'rm -rf "$(dirname "$TMP_BIN")"' EXIT

SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> Compiling UpdatePolicy tests…"
swiftc -target arm64-apple-macos13.0 -sdk "$SDK" -o "$TMP_BIN" \
  src/UpdatePolicy.swift tests/UpdatePolicyTests.swift

echo "==> Running UpdatePolicy tests…"
"$TMP_BIN"
