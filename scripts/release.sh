#!/bin/sh
# Builds a universal (Apple silicon + Intel) StorageAnalysis.app and packages it
# as dist/StorageAnalysis.dmg with an Applications shortcut for drag-to-install.
#
# The app is ad-hoc signed, not notarized (no Apple Developer ID), so users
# confirm it once via System Settings → Privacy & Security → Open Anyway.
set -eu

cd "$(dirname "$0")/.."

ARM="arm64-apple-macosx14.0"
INTEL="x86_64-apple-macosx14.0"

swift build -c release --product StorageAnalysis --triple "$ARM"
swift build -c release --product StorageAnalysis --triple "$INTEL"

APP="dist/StorageAnalysis.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS"
lipo -create \
  ".build/arm64-apple-macosx/release/StorageAnalysis" \
  ".build/x86_64-apple-macosx/release/StorageAnalysis" \
  -output "$APP/Contents/MacOS/StorageAnalysis"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# Disk image: the app plus an /Applications symlink to drag it onto.
STAGE="dist/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Storage Analysis" -srcfolder "$STAGE" -ov -format UDZO dist/StorageAnalysis.dmg >/dev/null
rm -rf "$STAGE"

lipo -archs "$APP/Contents/MacOS/StorageAnalysis"
ls -lh dist/StorageAnalysis.dmg
shasum -a 256 dist/StorageAnalysis.dmg
