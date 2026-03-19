#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/apple_build_common.sh"
BUILD_DIR="$ROOT_DIR/.build/xcframework"
DEVICE_ARCHIVE="$BUILD_DIR/ios_devices.xcarchive"
SIM_ARCHIVE="$BUILD_DIR/ios_simulator.xcarchive"
OUTPUT_DIR="$ROOT_DIR/Artifacts"
FRAMEWORK_NAME="MiniSwiftCompilerCore"

require_darwin_arm64_host
clear_inherited_apple_build_env

rm -rf "$BUILD_DIR" "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

xcodebuild_safe archive \
  -scheme "$FRAMEWORK_NAME" \
  -destination "generic/platform=iOS" \
  -archivePath "$DEVICE_ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ARCHS="$APPLE_ARCH" \
  ONLY_ACTIVE_ARCH=YES

xcodebuild_safe archive \
  -scheme "$FRAMEWORK_NAME" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$SIM_ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ARCHS="$APPLE_ARCH" \
  ONLY_ACTIVE_ARCH=YES

xcodebuild_safe -create-xcframework \
  -framework "$DEVICE_ARCHIVE/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
  -framework "$SIM_ARCHIVE/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
  -output "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"

echo "作成完了: $OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"

echo "swift-frontend adapter (.a + .h) のXCFrameworkを生成します"
"$ROOT_DIR/Scripts/build_swift_frontend_xcframework.sh"

echo "Swift runtime のXCFramework生成を試行します"
if ! "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"; then
  echo "警告: Swift runtime のXCFramework生成に失敗しました。環境依存のためスキップします。"
fi
