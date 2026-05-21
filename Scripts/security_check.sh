#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Superpaste.app}"

search_text() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$@"
  else
    grep -R -n -E "$pattern" "$@"
  fi
}

echo "Checking source for networking imports..."
if search_text 'import (Network|URLSession|CFNetwork)|URLSession|NWConnection|NSURLConnection' "$ROOT/Sources" "$ROOT/Package.swift"; then
  echo "Potential networking API reference found." >&2
  exit 1
fi

echo "Checking entitlements for network permissions..."
if search_text 'network\.client|network\.server' "$ROOT/Resources" "$ROOT/dist" 2>/dev/null; then
  echo "Network entitlement found." >&2
  exit 1
fi

if [[ -d "$APP" ]]; then
  EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || basename "$APP" .app)"
  echo "Inspecting linked libraries..."
  if otool -L "$APP/Contents/MacOS/$EXECUTABLE" | grep -E 'CFNetwork|Network\.framework'; then
    echo "Network framework linked." >&2
    exit 1
  fi
fi

echo "No networking APIs, frameworks, or entitlements detected."
