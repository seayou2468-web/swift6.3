#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/xcframework"
DEVICE_ARCHIVE="$BUILD_DIR/ios_devices.xcarchive"
SIM_ARCHIVE="$BUILD_DIR/ios_simulator.xcarchive"
OUTPUT_DIR="$ROOT_DIR/Artifacts"
FRAMEWORK_NAME="MiniSwiftCompilerCore"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

xcodebuild archive \
  -scheme "$FRAMEWORK_NAME" \
  -destination "generic/platform=iOS" \
  -archivePath "$DEVICE_ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild archive \
  -scheme "$FRAMEWORK_NAME" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$SIM_ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild -create-xcframework \
  -framework "$DEVICE_ARCHIVE/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
  -framework "$SIM_ARCHIVE/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
  -output "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"

echo "作成完了: $OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
