#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
PRODUCT_NAME="ClipShelf"
APP_NAME="Superpaste"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG" --arch arm64

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
for locale_dir in "$ROOT"/Resources/*.lproj; do
  [[ -d "$locale_dir" ]] || continue
  cp -R "$locale_dir" "$RESOURCES/"
done
touch "$APP_DIR"

echo "Signing $APP_DIR with identity: $CODESIGN_IDENTITY"
codesign --force --deep --options runtime \
  --entitlements "$ROOT/Resources/ClipShelf.entitlements" \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Built $APP_DIR"
echo "Use CODESIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' Scripts/build_app.sh for Developer ID signing."
