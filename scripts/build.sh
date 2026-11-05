#!/usr/bin/env bash
# Builds build/Ajar.app. Ad-hoc signed by default (local testing only).
# For a distributable build: AJAR_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID="io.github.mahit-c.ajar"
LABEL="io.github.mahit-c.ajar.helper"
SIGN_IDENTITY="${AJAR_SIGN_IDENTITY:--}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Ajar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/Ajar" "$BIN/AjarHelper" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "Resources/$LABEL.plist" "$APP/Contents/Library/LaunchDaemons/"
cp "Resources/$LABEL.legacy.plist" Resources/AppIcon.icns "$APP/Contents/Resources/"

SIGN_FLAGS=(--force --options runtime --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && SIGN_FLAGS+=(--timestamp)
codesign "${SIGN_FLAGS[@]}" --identifier "$LABEL" "$APP/Contents/MacOS/AjarHelper"
codesign "${SIGN_FLAGS[@]}" --identifier "$APP_ID" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signed: $SIGN_IDENTITY)"
