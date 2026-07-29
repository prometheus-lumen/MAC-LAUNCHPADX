#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/Release}"
APP_PATH="${APP_PATH:-$BUILD_DIR/LaunchpadX.app}"
OUTPUT_PATH="${OUTPUT_PATH:-$ROOT_DIR/build/LaunchpadX.dmg}"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "App not found: $APP_PATH"
  exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
codesign --force --deep --options runtime --sign - "$APP_PATH"
ditto "$APP_PATH" "$STAGING_DIR/LaunchpadX.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$OUTPUT_PATH"
hdiutil create -volname "LaunchpadX" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_PATH"
print "Created $OUTPUT_PATH"
