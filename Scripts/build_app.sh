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
ICON_COMPOSER_TOOL="${ICON_COMPOSER_TOOL:-/Applications/Icon Composer.app/Contents/Executables/ictool}"

cd "$ROOT"
swift build -c "$CONFIG" --arch arm64

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp -R "$ROOT/Resources/AppIcon.icon" "$RESOURCES/AppIcon.icon"

if [[ -d "$ROOT/Resources/AppIcon.icon" ]]; then
  if [[ ! -x "$ICON_COMPOSER_TOOL" ]]; then
    echo "error: Icon Composer ictool is required at $ICON_COMPOSER_TOOL." >&2
    echo "Install it with: brew install --cask icon-composer" >&2
    exit 1
  fi

  if ! ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
    echo "error: Xcode actool is required to compile native light/dark App Icon assets." >&2
    echo "Install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi

  ICON_WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$ICON_WORKDIR"' EXIT
  "$ICON_COMPOSER_TOOL" "$ROOT/Resources/AppIcon.icon" \
    --export-intermediate-representation \
    --platform macOS \
    --output-directory "$ICON_WORKDIR"
  ICON_XCASSETS="$ICON_WORKDIR/AppIcon.icon.xcassets"
  if [[ ! -d "$ICON_XCASSETS" ]]; then
    echo "error: Icon Composer did not generate $ICON_XCASSETS." >&2
    exit 1
  fi
  "$ACTOOL" \
    --compile "$RESOURCES" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_WORKDIR/AppIcon-PartialInfo.plist" \
    "$ICON_XCASSETS"
  if [[ ! -f "$RESOURCES/Assets.car" ]]; then
    echo "error: actool did not generate $RESOURCES/Assets.car." >&2
    exit 1
  fi
fi
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
