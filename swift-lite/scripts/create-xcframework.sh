#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LITE_DIR="$ROOT_DIR/swift-lite"
DIST_DIR="${DIST_DIR:-$LITE_DIR/out/swiftlite-dist}"
OUT_DIR="${OUT_DIR:-$LITE_DIR/out}"

xcodebuild -create-xcframework \
  -library "$DIST_DIR/lib/ios-arm64/libswiftlite.a" \
  -headers "$DIST_DIR/include" \
  -output "$OUT_DIR/swiftlite.xcframework"

echo "created: $OUT_DIR/swiftlite.xcframework"
