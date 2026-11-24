#!/bin/bash
# Installs or updates SidTree in /Applications from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/sidworks-dev/sidtree/main/scripts/install.sh | bash
# Files downloaded from Terminal are not quarantined, so macOS shows no "could not verify" warning.
set -euo pipefail
REPO="sidworks-dev/sidtree"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Looking up the latest SidTree release…"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')"
[ -n "$URL" ] || { echo "Could not find a release download."; exit 1; }

echo "▸ Downloading $(basename "$URL")…"
curl -fsSL "$URL" -o "$TMP/SidTree.zip"
ditto -x -k "$TMP/SidTree.zip" "$TMP/app"

osascript -e 'quit app "SidTree"' >/dev/null 2>&1 || true
rm -rf /Applications/SidTree.app
ditto "$TMP/app/SidTree.app" /Applications/SidTree.app
xattr -dr com.apple.quarantine /Applications/SidTree.app 2>/dev/null || true

echo "✓ Installed SidTree $(defaults read /Applications/SidTree.app/Contents/Info.plist CFBundleShortVersionString) in /Applications"
open /Applications/SidTree.app
