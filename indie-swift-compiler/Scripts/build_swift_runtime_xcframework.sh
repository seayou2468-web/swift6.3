#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/apple_build_common.sh"
OUT_DIR="$ROOT_DIR/Artifacts"
OUT_XC="$OUT_DIR/SwiftRuntimeCore.xcframework"
WORK_DIR="$ROOT_DIR/.build/swift-runtime"

require_darwin_arm64_host
clear_inherited_apple_build_env

SWIFT_FRONTEND="${SWIFT_FRONTEND_PATH:-$(xcrun --find swift-frontend 2>/dev/null || true)}"
if [[ -z "$SWIFT_FRONTEND" ]]; then
  SWIFT_FRONTEND="$(command -v swift-frontend || true)"
fi
if [[ -z "$SWIFT_FRONTEND" ]]; then
  echo "swift-frontend が見つからないため runtime bundling を続行できません"
  exit 1
fi

TOOLCHAIN_ROOT="$(cd "$(dirname "$SWIFT_FRONTEND")/.." && pwd)"
IOS_LIB="${SWIFT_RUNTIME_IOS_LIB:-$TOOLCHAIN_ROOT/lib/swift/iphoneos/libswiftCore.a}"
IOS_HEADERS="$WORK_DIR/include/iphoneos"

if [[ ! -f "$IOS_LIB" ]]; then
  echo "Swift runtime static library が見つかりません"
  echo "  IOS: $IOS_LIB"
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$OUT_XC"
rm -rf "$WORK_DIR"
mkdir -p "$IOS_HEADERS"

cat > "$IOS_HEADERS/SwiftRuntimeCore.h" <<'HEADER'
#pragma once
// Bundled Swift runtime entry header for iOS device.
// Linked archive: libswiftCore.a
HEADER

xcodebuild_safe -create-xcframework \
  -library "$IOS_LIB" -headers "$IOS_HEADERS" \
  -output "$OUT_XC"

echo "作成完了: $OUT_XC"
