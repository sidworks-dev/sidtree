#!/bin/bash
# Usage: scripts/release.sh 0.2.0
# Bumps VERSION, checks CHANGELOG.md has an entry, commits, tags and pushes.
# GitHub Actions then builds SidTree and publishes the release with the changelog notes.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/release.sh <version>}"
grep -q "^## \[$V\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$V]' section"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean"; exit 1; }
echo "$V" > VERSION
git add VERSION
git diff --cached --quiet || git commit -m "Release $V"
git tag "v$V"
git push origin HEAD "v$V"
echo "✓ Tagged v$V — GitHub Actions is building the release."
