#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CCodexUsageBar"
BUILD_DIR="$ROOT/build"
TMP_DIR="$BUILD_DIR/tmp"

UNIVERSAL_APP_DIR="$BUILD_DIR/$APP_NAME.app"
UNIVERSAL_ZIP="$BUILD_DIR/$APP_NAME-universal.zip"

ARM_BIN="$TMP_DIR/$APP_NAME-arm64"
X64_BIN="$TMP_DIR/$APP_NAME-x86_64"
UNIVERSAL_BIN="$TMP_DIR/$APP_NAME-universal"

rm -rf "$BUILD_DIR"
mkdir -p "$TMP_DIR"

SWIFT_SOURCES=("$ROOT"/Sources/*.swift)

swiftc \
  -target arm64-apple-macos12.0 \
  -o "$ARM_BIN" \
  "${SWIFT_SOURCES[@]}"

swiftc \
  -target x86_64-apple-macos12.0 \
  -o "$X64_BIN" \
  "${SWIFT_SOURCES[@]}"

lipo -create -output "$UNIVERSAL_BIN" "$ARM_BIN" "$X64_BIN"

create_app_bundle() {
  local app_dir="$1"
  local binary_path="$2"
  local macos_dir="$app_dir/Contents/MacOS"
  local res_dir="$app_dir/Contents/Resources"
  local target_bin="$macos_dir/$APP_NAME"

  mkdir -p "$macos_dir" "$res_dir"
  cp "$ROOT/Resources/Info.plist" "$app_dir/Contents/Info.plist"
  cp "$binary_path" "$target_bin"
  chmod +x "$target_bin"
}

zip_app_bundle() {
  local app_dir="$1"
  local zip_path="$2"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
}

create_app_bundle "$UNIVERSAL_APP_DIR" "$UNIVERSAL_BIN"
zip_app_bundle "$UNIVERSAL_APP_DIR" "$UNIVERSAL_ZIP"

file "$UNIVERSAL_BIN"
lipo -info "$UNIVERSAL_BIN"

rm -rf "$TMP_DIR"

echo "Built app:"
echo "  - $UNIVERSAL_APP_DIR"
echo "Built zip:"
echo "  - $UNIVERSAL_ZIP"
