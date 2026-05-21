#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Superpaste.app}"

echo "Checking source for networking imports..."
if rg -n 'import (Network|URLSession|CFNetwork)|URLSession|NWConnection|NSURLConnection' "$ROOT/Sources" "$ROOT/Package.swift"; then
  echo "Potential networking API reference found." >&2
  exit 1
fi

echo "Checking entitlements for network permissions..."
if rg -n 'network\.client|network\.server' "$ROOT/Resources" "$ROOT/dist" 2>/dev/null; then
  echo "Network entitlement found." >&2
  exit 1
fi

if [[ -d "$APP" ]]; then
  EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || basename "$APP" .app)"
  echo "Inspecting linked libraries..."
  if otool -L "$APP/Contents/MacOS/$EXECUTABLE" | rg 'CFNetwork|Network\.framework'; then
    echo "Network framework linked." >&2
    exit 1
  fi
fi

echo "No networking APIs, frameworks, or entitlements detected."
