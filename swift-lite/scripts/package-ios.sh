#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LITE_DIR="$ROOT_DIR/swift-lite"
BUILD_DIR="${BUILD_DIR:-$LITE_DIR/out/ios-arm64}"
DIST_DIR="${DIST_DIR:-$LITE_DIR/out/swiftlite-dist}"

mkdir -p "$DIST_DIR/include" "$DIST_DIR/lib/ios-arm64" "$DIST_DIR/runtime/ios"

cp "$LITE_DIR/include/swiftlite_compiler.h" "$DIST_DIR/include/"
cp "$LITE_DIR/include/swiftlite_errors.h" "$DIST_DIR/include/"
cp "$BUILD_DIR/libswiftlite.a" "$DIST_DIR/lib/ios-arm64/"

cat > "$DIST_DIR/runtime/ios/manifest.json" <<JSON
{
  "name": "swiftlite-runtime",
  "target": "ios-arm64",
  "note": "SDK is not bundled. Provide SDK path at runtime."
}
JSON

echo "packaged: $DIST_DIR"
