#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CCodexUsageBar"
MIN_MACOS="12.0"
BUILD_DIR="$ROOT/build"
TMP_DIR="$BUILD_DIR/tmp"

UNIVERSAL_APP_DIR="$BUILD_DIR/$APP_NAME.app"
UNIVERSAL_ZIP="$BUILD_DIR/$APP_NAME-universal.zip"

ARM_BIN="$TMP_DIR/$APP_NAME-arm64"
X64_BIN="$TMP_DIR/$APP_NAME-x86_64"
UNIVERSAL_BIN="$TMP_DIR/$APP_NAME-universal"
APP_BIN="$UNIVERSAL_APP_DIR/Contents/MacOS/$APP_NAME"
INFO_PLIST="$UNIVERSAL_APP_DIR/Contents/Info.plist"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required tool: $1" >&2
    exit 1
  }
}

verify_contains_arch() {
  local binary="$1"
  local arch="$2"
  lipo -info "$binary" | grep -q "$arch" || {
    echo "error: expected architecture '$arch' in $binary" >&2
    exit 1
  }
}

verify_bundle() {
  [[ -f "$APP_BIN" ]] || {
    echo "error: app binary missing: $APP_BIN" >&2
    exit 1
  }
  [[ -f "$INFO_PLIST" ]] || {
    echo "error: Info.plist missing: $INFO_PLIST" >&2
    exit 1
  }

  local executable
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")
  [[ "$executable" == "$APP_NAME" ]] || {
    echo "error: CFBundleExecutable mismatch: expected $APP_NAME got $executable" >&2
    exit 1
  }

  local min_version
  min_version=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")
  [[ "$min_version" == "$MIN_MACOS" ]] || {
    echo "error: LSMinimumSystemVersion mismatch: expected $MIN_MACOS got $min_version" >&2
    exit 1
  }

  verify_contains_arch "$APP_BIN" "arm64"
  verify_contains_arch "$APP_BIN" "x86_64"
}

rm -rf "$BUILD_DIR"
mkdir -p "$TMP_DIR"

require_tool swiftc
require_tool lipo
require_tool ditto
require_tool file
require_tool /usr/libexec/PlistBuddy

SWIFT_SOURCES=("$ROOT"/Sources/*.swift)

swiftc \
  -target arm64-apple-macos${MIN_MACOS} \
  -o "$ARM_BIN" \
  "${SWIFT_SOURCES[@]}"

swiftc \
  -target x86_64-apple-macos${MIN_MACOS} \
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
verify_bundle
zip_app_bundle "$UNIVERSAL_APP_DIR" "$UNIVERSAL_ZIP"

file "$UNIVERSAL_BIN"
lipo -info "$UNIVERSAL_BIN"
file "$APP_BIN"

rm -rf "$TMP_DIR"

echo "Built app:"
echo "  - $UNIVERSAL_APP_DIR"
echo "Built zip:"
echo "  - $UNIVERSAL_ZIP"
echo "Verified architectures: arm64 + x86_64"
echo "Minimum macOS: $MIN_MACOS"
