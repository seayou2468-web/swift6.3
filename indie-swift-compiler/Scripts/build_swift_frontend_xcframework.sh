#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/swift-frontend"
OUT_DIR="$ROOT_DIR/Artifacts"
HEADERS_DIR="$ROOT_DIR/Native/SwiftIRGenAdapter"
SRC_FILE="$ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp"
FRAMEWORK_OUT="$OUT_DIR/SwiftFrontend.xcframework"

IOS_BUILD="$BUILD_ROOT/ios"
SIM_BUILD="$BUILD_ROOT/ios-sim"
IOS_PREFIX="$IOS_BUILD/install"
SIM_PREFIX="$SIM_BUILD/install"

rm -rf "$BUILD_ROOT" "$FRAMEWORK_OUT"
mkdir -p "$IOS_BUILD" "$SIM_BUILD" "$OUT_DIR"

cat > "$BUILD_ROOT/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.20)
project(SwiftFrontendAdapter LANGUAGES CXX)

add_library(SwiftFrontendAdapter STATIC
  $SRC_FILE
)

target_include_directories(SwiftFrontendAdapter PUBLIC
  $HEADERS_DIR
)

target_compile_features(SwiftFrontendAdapter PRIVATE cxx_std_17)
set_target_properties(SwiftFrontendAdapter PROPERTIES OUTPUT_NAME SwiftFrontend)

install(TARGETS SwiftFrontendAdapter ARCHIVE DESTINATION lib)
install(FILES $HEADERS_DIR/SwiftIRGenAdapter.h DESTINATION include)
CMAKE

cmake -S "$BUILD_ROOT" -B "$IOS_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$IOS_PREFIX"
cmake --build "$IOS_BUILD" --target SwiftFrontendAdapter
cmake --install "$IOS_BUILD"

cmake -S "$BUILD_ROOT" -B "$SIM_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SIM_PREFIX"
cmake --build "$SIM_BUILD" --target SwiftFrontendAdapter
cmake --install "$SIM_BUILD"

xcodebuild -create-xcframework \
  -library "$IOS_PREFIX/lib/libSwiftFrontend.a" -headers "$IOS_PREFIX/include" \
  -library "$SIM_PREFIX/lib/libSwiftFrontend.a" -headers "$SIM_PREFIX/include" \
  -output "$FRAMEWORK_OUT"

echo "作成完了: $FRAMEWORK_OUT"
