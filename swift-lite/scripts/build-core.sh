#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LITE_DIR="$ROOT_DIR/swift-lite"
BUILD_DIR="${BUILD_DIR:-$LITE_DIR/out/ios-arm64}"
IOS_MIN="${IOS_MIN:-17.0}"

mkdir -p "$BUILD_DIR"

cmake -S "$LITE_DIR" -B "$BUILD_DIR" \
  -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD_DIR" --target swiftlite -j"$(sysctl -n hw.ncpu)"

echo "built: $BUILD_DIR/libswiftlite.a"
