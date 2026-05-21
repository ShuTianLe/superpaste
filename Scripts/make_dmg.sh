#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Superpaste.app"
DMG="$ROOT/dist/Superpaste.dmg"
STAGING="$ROOT/dist/dmg-stage"
VOLUME_NAME="Superpaste"
WINDOW_WIDTH=640
WINDOW_HEIGHT=420
APPLICATIONS_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"

"$ROOT/Scripts/build_app.sh"

rm -f "$DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"

osascript <<OSA
tell application "Finder"
  make new alias file to POSIX file "/Applications" at POSIX file "$STAGING" with properties {name:"Applications"}
end tell
OSA

ICON_WORKDIR="$(mktemp -d)"
trap 'rm -rf "$ICON_WORKDIR"' EXIT
cp "$APPLICATIONS_ICON" "$ICON_WORKDIR/ApplicationsFolderIcon.icns"
sips -i "$ICON_WORKDIR/ApplicationsFolderIcon.icns" >/dev/null
DeRez -only icns "$ICON_WORKDIR/ApplicationsFolderIcon.icns" > "$ICON_WORKDIR/ApplicationsIcon.rsrc"
Rez -append "$ICON_WORKDIR/ApplicationsIcon.rsrc" -o "$STAGING/Applications"
SetFile -a C "$STAGING/Applications"

TMP_DMG="$ROOT/dist/Superpaste.tmp.dmg"
rm -f "$TMP_DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDRW "$TMP_DMG" -quiet

MOUNT_DIR="/Volumes/$VOLUME_NAME"
hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
hdiutil attach "$TMP_DMG" -nobrowse -quiet

osascript <<OSA || echo "Finder layout customization skipped; drag-to-Applications layout is still present."
tell application "Finder"
  tell disk "$VOLUME_NAME"
	    open
	    set current view of container window to icon view
	    set toolbar visible of container window to false
	    set statusbar visible of container window to false
	    set bounds of container window to {120, 120, 120 + $WINDOW_WIDTH, 120 + $WINDOW_HEIGHT}
	    set viewOptions to the icon view options of container window
	    set arrangement of viewOptions to not arranged
	    set icon size of viewOptions to 96
	    set position of item "Superpaste.app" of container window to {190, 210}
	    set position of item "Applications" of container window to {450, 210}
	    close
	    open
    update without registering applications
    delay 0.8
  end tell
end tell
OSA

hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG" -quiet
rm -f "$TMP_DMG"
rm -rf "$STAGING"
echo "Created $DMG"
