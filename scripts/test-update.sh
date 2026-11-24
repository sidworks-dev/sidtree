#!/bin/bash
# Try the whole update flow locally, without publishing a release:
#   scripts/test-update.sh [from-version] [to-version]      (default 0.1.0 → 0.2.0)
#
# Installs SidTree <from> in build/update-test/Applications and serves SidTree <to> from a local
# release feed. Uses its own bundle id, so your real settings and installed app are not touched.
set -euo pipefail
cd "$(dirname "$0")/.."

FROM="${1:-0.1.0}"
TO="${2:-0.2.0}"
ID="nl.sidworks.sidtree.updatetest"
W="$PWD/build/update-test"
export ARCHS="${ARCHS:-$(uname -m)}"

retag() { # bundle-id + re-sign a built app
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$1/Contents/Info.plist"
    codesign --force --sign - "$1" >/dev/null 2>&1
}

pkill -f "$W/Applications/SidTree.app" 2>/dev/null || true
rm -rf "$W" && mkdir -p "$W/feed" "$W/Applications"
defaults delete "$ID" >/dev/null 2>&1 || true

echo "▸ Building the new version ${TO}…"
SIDTREE_VERSION="$TO" ./scripts/build.sh >/dev/null
# Give the new build a What's New entry for this test.
NOTES="### Added
- Test update from $FROM to $TO
- Everything currently in your working copy"
{ printf '# Changelog\n\n## [%s] - %s\n\n%s\n\n' "$TO" "$(date +%Y-%m-%d)" "$NOTES"; tail -n +2 CHANGELOG.md; } \
    > build/SidTree.app/Contents/Resources/CHANGELOG.md
retag build/SidTree.app
ditto -c -k --keepParent build/SidTree.app "$W/feed/SidTree-$TO.zip"

cat > "$W/feed/release.json" <<JSON
{
  "tag_name": "v$TO",
  "html_url": "https://github.com/sidworks-dev/sidtree/releases",
  "body": $(printf '%s' "$NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "assets": [{ "name": "SidTree-$TO.zip", "browser_download_url": "file://$W/feed/SidTree-$TO.zip" }]
}
JSON

echo "▸ Building the installed version ${FROM}…"
SIDTREE_VERSION="$FROM" ./scripts/build.sh >/dev/null
ditto build/SidTree.app "$W/Applications/SidTree.app"
retag "$W/Applications/SidTree.app"

echo "▸ Starting SidTree ${FROM} with the local update feed…"
SIDTREE_UPDATE_FEED="$W/feed/release.json" nohup "$W/Applications/SidTree.app/Contents/MacOS/SidTree" >/dev/null 2>&1 &

cat <<MSG

✓ SidTree $FROM is running from build/update-test/Applications.
  The update window opens by itself (startup check). Click "Install & Relaunch":
  SidTree quits, is replaced by $TO, reopens and shows What's New.

  Run "./scripts/build.sh" afterwards to rebuild your normal app.
MSG
