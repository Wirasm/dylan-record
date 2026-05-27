#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DylanRecord"
SCHEME="$APP_NAME"
CONFIGURATION="Release"
DERIVED="build"
DEST="/Applications/${APP_NAME}.app"

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

BUILT_APP="$DERIVED/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build succeeded but $BUILT_APP not found" >&2
  exit 1
fi

echo "==> Ad-hoc signing (hardened runtime)"
codesign --force --deep --sign - --options runtime \
  --entitlements "${APP_NAME}/${APP_NAME}.entitlements" \
  "$BUILT_APP"

echo "==> Stopping any running instance"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

echo "==> Done. Launch from Launchpad or: open \"$DEST\""
