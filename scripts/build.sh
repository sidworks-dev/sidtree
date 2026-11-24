#!/bin/bash
# Builds SidTree.app without Xcode/SwiftPM (only Command Line Tools needed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/SidTree.app"
VERSION="${SIDTREE_VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
OPT=(-O -wmo)
[ "$CONFIG" = "debug" ] && OPT=(-Onone -g)
# STRICT=1 (used by scripts/check.sh and CI) turns every compiler warning into an error.
[ "${STRICT:-0}" = "1" ] && OPT+=(-warnings-as-errors)

# SDK 27's SwiftUI implements @State as a macro whose plugin only ships with Xcode.
# With only Command Line Tools installed, build against the newest SDK 26.x instead.
if [ -z "${SDK:-}" ]; then
  SDK="$(xcrun --show-sdk-path)"
  if [ ! -d /Applications/Xcode.app ]; then
    CANDIDATE="$(find /Library/Developer/CommandLineTools/SDKs -maxdepth 1 -name 'MacOSX26.*.sdk' 2>/dev/null | sort -V | tail -1)"
    [ -n "$CANDIDATE" ] && SDK="$CANDIDATE"
  fi
fi
echo "▸ SDK: $SDK"

mkdir -p build
# Release builds are universal (Apple Silicon + Intel); debug builds only the local architecture.
read -r -a ARCH_LIST <<< "${ARCHS:-$([ "$CONFIG" = "debug" ] && uname -m || echo "arm64 x86_64")}"
echo "▸ Compiling ($CONFIG, ${ARCH_LIST[*]})…"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Sources/SidTree -name '*.swift' | sort)
PIDS=()
BINARIES=()
for ARCH in "${ARCH_LIST[@]}"; do
  mkdir -p "build/$ARCH"
  swiftc "${OPT[@]}" -parse-as-library -swift-version 5 -sdk "$SDK" \
    -target "$ARCH-apple-macosx14.0" \
    -module-name SidTree \
    -module-cache-path "build/$ARCH/ModuleCache" \
    "${SOURCES[@]}" \
    -o "build/$ARCH/SidTree" &
  PIDS+=($!)
  BINARIES+=("build/$ARCH/SidTree")
done
for PID in "${PIDS[@]}"; do wait "$PID"; done
lipo -create "${BINARIES[@]}" -output build/SidTree

echo "▸ Bundling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/SidTree "$APP/Contents/MacOS/SidTree"
cp Resources/sidworks-logo.tiff "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/"
cp scripts/sidtree "$APP/Contents/Resources/sidtree"
chmod +x "$APP/Contents/Resources/sidtree"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SidTree</string>
  <key>CFBundleDisplayName</key><string>SidTree</string>
  <key>CFBundleIdentifier</key><string>nl.sidworks.sidtree</string>
  <key>CFBundleExecutable</key><string>SidTree</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>nl.sidworks.sidtree.file-drag</string>
      <key>UTTypeDescription</key><string>SidTree file selection</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ Built $APP"
