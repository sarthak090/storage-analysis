#!/bin/sh
# Builds the SwiftPM executable and wraps it in build/StorageAnalysis.app.
# Non-sandboxed, ad-hoc signed, local use only (PLAN.md §3).
set -eu

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/StorageAnalysis"

APP="build/StorageAnalysis.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/StorageAnalysis"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature, no entitlements => not sandboxed.
codesign --force --sign - "$APP"

echo "Built $APP — run: open $APP"
