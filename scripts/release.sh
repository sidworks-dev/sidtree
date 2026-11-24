#!/bin/bash
# Usage: scripts/release.sh 0.6.0
# Bumps VERSION, checks CHANGELOG.md has an entry, commits and pushes.
# The VERSION change triggers GitHub Actions, which builds SidTree and publishes release v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/release.sh <version>}"
grep -q "^## \[$V\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$V]' section"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean"; exit 1; }
echo "$V" > VERSION
git add VERSION
git diff --cached --quiet || git commit -m "Release $V"
git push origin HEAD
echo "✓ Pushed $V — GitHub Actions is building release v$V."
