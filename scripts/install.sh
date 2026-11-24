#!/bin/bash
# Installs or updates SidTree in /Applications from the latest GitHub release.
# Downloaded with the GitHub CLI, so macOS shows no "could not verify" warning.
set -euo pipefail
command -v gh >/dev/null || { echo "The GitHub CLI is needed: brew install gh && gh auth login"; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "▸ Downloading the latest SidTree…"
gh release download -R sidworks-dev/sidtree -p 'SidTree-*.zip' -D "$TMP"
ditto -x -k "$TMP"/SidTree-*.zip "$TMP/app"
osascript -e 'quit app "SidTree"' >/dev/null 2>&1 || true
rm -rf /Applications/SidTree.app
ditto "$TMP/app/SidTree.app" /Applications/SidTree.app
xattr -dr com.apple.quarantine /Applications/SidTree.app 2>/dev/null || true
echo "✓ Installed $(defaults read /Applications/SidTree.app/Contents/Info.plist CFBundleShortVersionString) in /Applications"
open /Applications/SidTree.app
