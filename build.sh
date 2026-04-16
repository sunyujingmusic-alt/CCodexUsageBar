#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CCodexUsageBar"
BUILD_DIR="$ROOT/build"
TMP_DIR="$BUILD_DIR/tmp"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BIN="$MACOS_DIR/$APP_NAME"
ARM_BIN="$TMP_DIR/$APP_NAME-arm64"
X64_BIN="$TMP_DIR/$APP_NAME-x86_64"

rm -rf "$APP_DIR" "$TMP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR" "$TMP_DIR"

SWIFT_SOURCES=("$ROOT"/Sources/*.swift)

swiftc \
  -target arm64-apple-macos12.0 \
  -o "$ARM_BIN" \
  "${SWIFT_SOURCES[@]}"

swiftc \
  -target x86_64-apple-macos12.0 \
  -o "$X64_BIN" \
  "${SWIFT_SOURCES[@]}"

lipo -create -output "$BIN" "$ARM_BIN" "$X64_BIN"
chmod +x "$BIN"

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built: $APP_DIR"
file "$BIN"
lipo -info "$BIN"
