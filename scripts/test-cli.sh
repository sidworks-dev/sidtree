#!/bin/bash
# Exercise the bundled launcher without opening any real applications.
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
TEST_TMP="$(cd -P "$TEST_TMP" && pwd)"
TEST_APP="$TEST_TMP/SidTree.app"
TEST_REPO="$TEST_TMP/repo with spaces"
TEST_BIN="$TEST_TMP/bin with spaces"
TEST_LAUNCHER="$TEST_APP/Contents/Resources/sidtree"
export SIDTREE_TEST_OPEN_LOG="$TEST_TMP/open.log"
mkdir -p "$TEST_APP/Contents/Resources" "$TEST_TMP/fake-bin" "$TEST_TMP/not-a-repository"
cp scripts/sidtree "$TEST_LAUNCHER"
chmod +x "$TEST_LAUNCHER"
cat > "$TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>0.5.0</string></dict></plist>
PLIST
cat > "$TEST_TMP/fake-bin/open" <<'OPEN'
#!/bin/sh
printf '%s\n' "$@" > "$SIDTREE_TEST_OPEN_LOG"
OPEN
chmod +x "$TEST_TMP/fake-bin/open"
export PATH="$TEST_TMP/fake-bin:$PATH"
git init -q "$TEST_REPO"
mkdir -p "$TEST_REPO/src/nested" "$TEST_REPO/-directory"
touch "$TEST_REPO/src/nested/file with spaces.swift"
printf '%s\n' -a "$TEST_APP" "$TEST_REPO" > "$TEST_TMP/expected-open.log"

check_open() {
    local directory="$1"
    shift
    rm -f "$SIDTREE_TEST_OPEN_LOG"
    (cd "$directory" && "$TEST_LAUNCHER" "$@")
    cmp "$TEST_TMP/expected-open.log" "$SIDTREE_TEST_OPEN_LOG"
}

check_failure() {
    rm -f "$SIDTREE_TEST_OPEN_LOG"
    if "$TEST_LAUNCHER" "$@" > "$TEST_TMP/error.log" 2>&1; then
        echo "FAIL: expected an error for $*" >&2
        exit 1
    fi
    [ ! -e "$SIDTREE_TEST_OPEN_LOG" ]
}

check_open "$TEST_REPO"
check_open "$TEST_REPO/src/nested"
check_open "$TEST_TMP" "$TEST_REPO"
check_open "$TEST_REPO" src/nested
check_open "$TEST_REPO" 'src/nested/file with spaces.swift'
check_open "$TEST_REPO" -- -directory
echo "✓ Current, explicit, nested, file and dash-prefixed paths open the repository"

check_failure "$TEST_TMP/not-a-repository"
check_failure "$TEST_TMP/missing"
check_failure --unknown-option
check_failure one two
"$TEST_LAUNCHER" --help > "$TEST_TMP/help.log"
"$TEST_LAUNCHER" -h > "$TEST_TMP/help-short.log"
cmp "$TEST_TMP/help.log" "$TEST_TMP/help-short.log"
[ ! -e "$SIDTREE_TEST_OPEN_LOG" ]
if [ "$(uname -s)" = Darwin ]; then
    [ "$("$TEST_LAUNCHER" --version)" = 'sidtree version 0.5.0' ]
    [ "$("$TEST_LAUNCHER" -v)" = 'sidtree version 0.5.0' ]
fi
echo "✓ Invalid input fails without launching the app; help and version work"

"$TEST_LAUNCHER" --install "$TEST_BIN" > "$TEST_TMP/install.log"
[ "$(readlink "$TEST_BIN/sidtree")" = "$TEST_LAUNCHER" ]
"$TEST_LAUNCHER" --install "$TEST_BIN" > "$TEST_TMP/install.log"
(cd "$TEST_REPO/src" && "$TEST_BIN/sidtree")
cmp "$TEST_TMP/expected-open.log" "$SIDTREE_TEST_OPEN_LOG"
mkdir -p "$TEST_TMP/relative-bin"
ln -s '../bin with spaces/sidtree' "$TEST_TMP/relative-bin/sidtree"
(cd "$TEST_REPO" && "$TEST_TMP/relative-bin/sidtree" .)
cmp "$TEST_TMP/expected-open.log" "$SIDTREE_TEST_OPEN_LOG"
echo "✓ Installation is repeatable and launchers follow absolute and relative symlinks"

rm "$TEST_BIN/sidtree"
ln -s /missing/SidTree.app/Contents/Resources/sidtree "$TEST_BIN/sidtree"
"$TEST_LAUNCHER" --install "$TEST_BIN" > "$TEST_TMP/install.log"
[ "$(readlink "$TEST_BIN/sidtree")" = "$TEST_LAUNCHER" ]
rm "$TEST_BIN/sidtree"
printf 'keep this file\n' > "$TEST_BIN/sidtree"
check_failure --install "$TEST_BIN"
[ "$(cat "$TEST_BIN/sidtree")" = 'keep this file' ]
rm "$TEST_BIN/sidtree"
ln -s /another/command "$TEST_BIN/sidtree"
check_failure --install "$TEST_BIN"
[ "$(readlink "$TEST_BIN/sidtree")" = /another/command ]
echo "✓ Old SidTree links are updated; other files and symlinks are preserved"
echo "✓ All CLI checks passed"
