#!/usr/bin/env bash
# Signed + notarized DMG for public download. UNTESTED until a Developer ID exists.
# Prereqs:
#   1. Set AjarConstants.teamID in Sources/AjarShared/HelperProtocol.swift
#   2. xcrun notarytool store-credentials ajar-notary --apple-id ... --team-id ...
#   3. AJAR_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${AJAR_SIGN_IDENTITY:?Set AJAR_SIGN_IDENTITY to your Developer ID Application identity}"
if grep -q 'teamID: String? = nil' Sources/AjarShared/HelperProtocol.swift; then
  echo "Refusing to release: AjarConstants.teamID is nil, so the helper would trust any app named io.github.mahit-c.ajar." >&2
  exit 1
fi

scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Ajar-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R build/Ajar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname Ajar -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$AJAR_SIGN_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile ajar-notary --wait
xcrun stapler staple "$DMG"
echo "Release ready: $DMG"
