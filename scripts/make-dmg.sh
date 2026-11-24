#!/bin/bash
# Packages build/SidTree.app into build/SidTree-<version>.dmg with a drag-to-Applications window.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
APP="build/SidTree.app"
OUT="build/SidTree-$VERSION.dmg"
RW="build/SidTree-rw.dmg"
STAGE="build/dmg"
[ -d "$APP" ] || { echo "Build the app first: scripts/build.sh"; exit 1; }

rm -rf "$STAGE" "$RW" "$OUT"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/SidTree.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/dmg-background.tiff "$STAGE/.background/background.tiff"

echo "▸ Creating disk image…"
hdiutil create -volname "SidTree" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
DEVICE="$(echo "$ATTACH" | grep -E '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="$(echo "$ATTACH" | grep -E '/Volumes/' | sed -E 's#.*(/Volumes/.*)$#\1#' | head -1)"
DISK="$(basename "$MOUNT")"

# Window layout: app on the left, Applications on the right, arrow background. Best effort:
# without Finder access (or in a headless session) the image still works, just without the layout.
osascript <<OSA >/dev/null 2>&1 || echo "  (Finder layout skipped)"
tell application "Finder"
    tell disk "$DISK"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "SidTree.app" of container window to {170, 190}
        set position of item "Applications" of container window to {490, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

sync
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"
echo "✓ Built $OUT"
