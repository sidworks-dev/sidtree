#!/bin/bash
# Quality gate. Fails on any compiler warning, SwiftLint violation or ShellCheck finding.
#   scripts/check.sh
# Needs SwiftLint and ShellCheck: brew install swiftlint shellcheck
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
FAILED=0
step() { printf '\n▸ %s\n' "$1"; }
fail() { echo "✗ $1"; FAILED=1; }

step "Compiling with warnings as errors"
if STRICT=1 ARCHS="$(uname -m)" ./scripts/build.sh release >build/check-compile.log 2>&1; then
    echo "✓ No compiler warnings"
else
    grep -E "error|warning" build/check-compile.log | head -40
    fail "Compiler warnings or errors (full log: build/check-compile.log)"
fi

step "SwiftLint"
if command -v swiftlint >/dev/null; then
    # Without Xcode, SwiftLint finds SourceKit in the Command Line Tools.
    [ -d /Applications/Xcode.app ] || export TOOLCHAIN_DIR=/Library/Developer/CommandLineTools
    if swiftlint lint --strict --quiet; then echo "✓ SwiftLint clean"; else fail "SwiftLint violations"; fi
else
    fail "SwiftLint is not installed (brew install swiftlint)"
fi

step "ShellCheck"
if command -v shellcheck >/dev/null; then
    if shellcheck scripts/*.sh scripts/sidtree; then echo "✓ ShellCheck clean"; else fail "ShellCheck findings"; fi
else
    fail "ShellCheck is not installed (brew install shellcheck)"
fi

step "CLI launcher"
if ./scripts/test-cli.sh; then echo "✓ CLI checks clean"; else fail "CLI launcher checks"; fi

echo
if [ "$FAILED" = 0 ]; then echo "✓ All quality checks passed"; else echo "✗ Quality checks failed"; fi
exit "$FAILED"
