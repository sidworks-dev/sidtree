#!/bin/bash
# Usage: scripts/release.sh 0.6.0
#
# Builds SidTree on this Mac and publishes GitHub release v<version> with the .dmg and .zip
# and the notes from CHANGELOG.md. Local builds take about a minute and never wait in
# GitHub's queue for a macOS runner. The VERSION commit is pushed with [skip ci].
# (The GitHub workflow can still build a release: Actions → Release → Run workflow.)
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/release.sh <version>}"
REPO="sidworks-dev/sidtree"

command -v gh >/dev/null || { echo "The GitHub CLI is needed to publish: brew install gh && gh auth login"; exit 1; }
grep -q "^## \[$V\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$V]' section"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean"; exit 1; }
if gh release view "v$V" -R "$REPO" >/dev/null 2>&1; then echo "Release v$V already exists"; exit 1; fi

if [ "$(tr -d '[:space:]' < VERSION)" != "$V" ]; then
    echo "$V" > VERSION
    git add VERSION
    git commit -q -m "Release $V [skip ci]"
fi
git push -q origin HEAD

echo "▸ Building SidTree $V (universal)…"
./scripts/build.sh release
ditto -c -k --keepParent build/SidTree.app "build/SidTree-$V.zip"
./scripts/make-dmg.sh

awk -v v="$V" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## / { exit }
    on { print }
' CHANGELOG.md > build/release-notes.md

echo "▸ Publishing v$V…"
gh release create "v$V" "build/SidTree-$V.dmg" "build/SidTree-$V.zip" -R "$REPO" \
    --target "$(git rev-parse HEAD)" --title "SidTree $V" --notes-file build/release-notes.md
echo "✓ Released SidTree $V"
