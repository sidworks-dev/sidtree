#!/bin/bash
# Native file URL, staging payload and mouse/keyboard interaction checks (macOS).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_SDK="${SDK:-$(xcrun --show-sdk-path)}"
if [ ! -d /Applications/Xcode.app ]; then
    TEST_CANDIDATE="$(find /Library/Developer/CommandLineTools/SDKs -maxdepth 1 -name 'MacOSX26.*.sdk' | sort -V | tail -1)"
    [ -z "$TEST_CANDIDATE" ] || TEST_SDK="$TEST_CANDIDATE"
fi
TEST_APP="build/file-drag-tests/FileDragTests.app"
mkdir -p "$TEST_APP/Contents/MacOS" build/file-drag-tests/ModuleCache
cat > "$TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>nl.sidworks.sidtree.file-drag-tests</string>
<key>CFBundleExecutable</key><string>FileDragTests</string>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>nl.sidworks.sidtree.file-drag</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>
</dict></plist>
PLIST
swiftc -warnings-as-errors -parse-as-library -swift-version 5 -sdk "$TEST_SDK" \
    -target "$(uname -m)-apple-macosx14.0" -module-cache-path build/file-drag-tests/ModuleCache \
    Sources/SidTree/Git/Models.swift Sources/SidTree/Views/Theme.swift \
    Sources/SidTree/Views/FileDrag.swift Sources/SidTree/Views/FileListView.swift \
    Sources/SidTree/Views/FileMarqueeSelection.swift Tests/FileDragTests.swift \
    -o "$TEST_APP/Contents/MacOS/FileDragTests"
"$TEST_APP/Contents/MacOS/FileDragTests"
