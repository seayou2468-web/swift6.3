#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/apple_build_common.sh"
BUILD_ROOT="$ROOT_DIR/.build/swift-frontend"
OUT_DIR="$ROOT_DIR/Artifacts"
HEADERS_DIR="$ROOT_DIR/Native/SwiftIRGenAdapter"
SRC_FILE="$ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp"
FRAMEWORK_OUT="$OUT_DIR/SwiftFrontend.xcframework"
EMBEDDED_IOS_LIB="${SWIFT_FRONTEND_EMBEDDED_LIB_IOS:-}"

HOST_BUILD="$BUILD_ROOT/native-host"
IOS_BUILD="$BUILD_ROOT/ios"
HOST_PREFIX="$HOST_BUILD/install"
IOS_PREFIX="$IOS_BUILD/install"
IOS_ADAPTER_LIB="$IOS_PREFIX/lib/libSwiftFrontendAdapter.a"
IOS_UNIFIED_LIB="$IOS_PREFIX/lib/libSwiftFrontend.a"

require_darwin_arm64_host
clear_inherited_apple_build_env
configure_host_apple_cmake_flags
configure_optional_compiler_launcher_flags

rm -rf "$BUILD_ROOT" "$FRAMEWORK_OUT"
mkdir -p "$HOST_BUILD" "$IOS_BUILD" "$OUT_DIR"

if [[ -z "$EMBEDDED_IOS_LIB" ]]; then
  echo "エラー: 実体同梱が必須です。"
  echo "SWIFT_FRONTEND_EMBEDDED_LIB_IOS を指定してください。"
  exit 1
fi

if [[ ! -f "$EMBEDDED_IOS_LIB" ]]; then
  echo "エラー: 指定された実体ライブラリが見つかりません。"
  echo "  iOS: $EMBEDDED_IOS_LIB"
  exit 1
fi

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

host_cmake_args=(
  -S "$BUILD_ROOT"
  -B "$HOST_BUILD"
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$HOST_PREFIX"
)
host_cmake_args+=("${APPLE_HOST_STAGE_CMAKE_FLAGS[@]}")
if [[ ${#CMAKE_LAUNCHER_FLAGS[@]} -gt 0 ]]; then
  host_cmake_args+=("${CMAKE_LAUNCHER_FLAGS[@]}")
fi
cmake "${host_cmake_args[@]}"
cmake_build "$HOST_BUILD" --target SwiftFrontendAdapter
cmake --install "$HOST_BUILD"

configure_cross_apple_cmake_flags iphoneos
ios_cmake_args=(
  -S "$BUILD_ROOT"
  -B "$IOS_BUILD"
  -G Ninja
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$IOS_PREFIX"
)
ios_cmake_args+=("${APPLE_CROSS_STAGE_CMAKE_FLAGS[@]}")
if [[ ${#CMAKE_LAUNCHER_FLAGS[@]} -gt 0 ]]; then
  ios_cmake_args+=("${CMAKE_LAUNCHER_FLAGS[@]}")
fi
cmake "${ios_cmake_args[@]}"
cmake_build "$IOS_BUILD" --target SwiftFrontendAdapter
cmake --install "$IOS_BUILD"
mv "$IOS_UNIFIED_LIB" "$IOS_ADAPTER_LIB"
libtool -static -o "$IOS_UNIFIED_LIB" "$IOS_ADAPTER_LIB" "$EMBEDDED_IOS_LIB"

for lib in "$IOS_UNIFIED_LIB"; do
  if ! nm -gU "$lib" 2>/dev/null | grep -q "swift_frontend_embedded_compile"; then
    echo "エラー: $lib に swift_frontend_embedded_compile が含まれていません。"
    exit 1
  fi
  if ! nm -gU "$lib" 2>/dev/null | grep -q "swift_frontend_embedded_emit_sil"; then
    echo "エラー: $lib に swift_frontend_embedded_emit_sil が含まれていません。"
    exit 1
  fi
done

xcodebuild_safe -create-xcframework \
  -library "$IOS_PREFIX/lib/libSwiftFrontend.a" -headers "$IOS_PREFIX/include" \
  -output "$FRAMEWORK_OUT"

echo "作成完了: $FRAMEWORK_OUT"
