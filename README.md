# Superpaste

Superpaste is a lightweight, local-only clipboard history app for macOS. It is built with SwiftUI + AppKit, targets macOS 14+, and ships Apple Silicon (`arm64`) builds only.

The app is inspired by the fast Paste-style workflow: press `Shift-Command-V`, browse recent clipboard history in a bottom panel, then press `Enter` or a number key to paste the selected item back into the app you were using.

## 1.0 Highlights

- Menu bar app with no main window.
- Global `Shift-Command-V` hotkey.
- Full-width bottom clipboard panel with keyboard-first card selection.
- Recent clipboard history for text, links, rich text, HTML, files, PDFs, images, colors, and generic pasteboard payloads.
- Direct paste into the previous input field using macOS Accessibility + `Command-V`.
- Copy-only fallback when Accessibility permission is not enabled.
- Search, type filters, source metadata, delete, pin, pinboard, and plain-text paste actions.
- Simplified Chinese and English UI, with an in-app language switch.
- Local OCR indexing for images through Apple Vision.
- SQLite metadata plus AES-GCM encrypted payload blobs.
- Keychain-backed encryption key.
- Ignored apps, sensitive regex rules, and transient/concealed pasteboard skipping.
- No account, no sync, no telemetry, no networking SDK, and no network entitlement.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Swift 5.9+ toolchain for development
- Accessibility permission for direct paste

## Build

Build the SwiftPM product:

```bash
swift build -c release --arch arm64
```

Build a signed `.app` bundle:

```bash
Scripts/build_app.sh
```

Create a drag-to-Applications DMG:

```bash
Scripts/make_dmg.sh
```

The generated app and DMG are written to `dist/`, which is intentionally ignored by git.

## Development Checks

```bash
swift build
swift build -c release --arch arm64
swift run ClipShelfCoreSmokeTests
Scripts/build_app.sh
Scripts/make_dmg.sh
Scripts/security_check.sh
codesign --verify --deep --strict --verbose=4 dist/ClipShelf.app
```

## Accessibility Permission

Direct paste requires macOS Accessibility permission. If permission is missing, Superpaste still writes the selected item to the system clipboard and shows guidance to open System Settings.

For stable permission behavior, install and launch the app from:

```text
/Applications/ClipShelf.app
```

If you enable Accessibility while the app is running, quit and relaunch the app so macOS refreshes the permission state.

## Privacy

Superpaste is designed to run locally:

- Clipboard data is stored under `~/Library/Application Support/ClipShelf`.
- Payload files are encrypted with AES-GCM.
- The master key is stored in the local Keychain with device-only accessibility.
- The app does not request network entitlements.
- The repository includes `Scripts/security_check.sh` to guard against accidental networking imports, frameworks, or entitlements.

## Signing

By default, `Scripts/build_app.sh` uses ad-hoc signing for local builds. For distribution, pass a Developer ID identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" Scripts/build_app.sh
```

Then notarize the DMG with Apple's `notarytool`.

## Version

This repository is tagged `v1.0.0` for the first productized release.

## License

No license has been specified yet. All rights reserved unless a license file is added.
