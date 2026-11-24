#!/bin/bash
# Signs with a Developer ID certificate and notarizes with Apple, so macOS opens SidTree without warnings.
#   scripts/sign-and-notarize.sh app   → signs + notarizes + staples build/SidTree.app
#   scripts/sign-and-notarize.sh dmg   → signs + notarizes + staples build/SidTree-<version>.dmg
#
# Needs (GitHub secrets in CI):
#   MACOS_CERTIFICATE           base64 of a "Developer ID Application" .p12
#   MACOS_CERTIFICATE_PASSWORD  password of that .p12
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (app-specific password from appleid.apple.com)
set -euo pipefail
cd "$(dirname "$0")/.."
WHAT="${1:?usage: sign-and-notarize.sh app|dmg}"
: "${MACOS_CERTIFICATE:?}" "${MACOS_CERTIFICATE_PASSWORD:?}" "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"

KEYCHAIN="$RUNNER_TEMP/sidtree-signing.keychain-db"
if [ ! -f "$KEYCHAIN" ]; then
    KC_PASS="$(uuidgen)"
    echo "$MACOS_CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/cert.p12"
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
    security set-keychain-settings -lut 3600 "$KEYCHAIN"
    security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
    security import "$RUNNER_TEMP/cert.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
    security set-key-partition-list -S apple-tool:,apple: -k "$KC_PASS" "$KEYCHAIN" >/dev/null
    EXISTING=()
    while IFS= read -r chain; do EXISTING+=("$chain"); done < <(security list-keychains -d user | tr -d '" ')
    security list-keychains -d user -s "$KEYCHAIN" "${EXISTING[@]}"
    rm -f "$RUNNER_TEMP/cert.p12"
fi
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in the certificate"; exit 1; }

notarize() {
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
}

case "$WHAT" in
app)
    codesign --force --options runtime --timestamp --sign "$IDENTITY" build/SidTree.app
    ditto -c -k --keepParent build/SidTree.app "$RUNNER_TEMP/notarize.zip"
    notarize "$RUNNER_TEMP/notarize.zip"
    xcrun stapler staple build/SidTree.app
    ;;
dmg)
    DMG="build/SidTree-$(cat VERSION).dmg"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    ;;
esac
echo "✓ Signed and notarized ($WHAT)"
