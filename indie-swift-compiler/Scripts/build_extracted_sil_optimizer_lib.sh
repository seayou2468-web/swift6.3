#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="${1:-$ROOT_DIR/.toolchain-workspace}"
SCHEME="${2:-release/6.3}"

SWIFT_REPO="$WORKSPACE_DIR/swift"
LLVM_REPO="$WORKSPACE_DIR/llvm-project"
BUNDLE_DIR="$ROOT_DIR/Generated/SwiftSILExtract"
BUILD_DIR="$ROOT_DIR/.build/sil-optimizer-extract"
OUT_LIB="$BUILD_DIR/libSwiftSILOptimizer.a"

if [[ ! -d "$SWIFT_REPO" || ! -d "$LLVM_REPO" ]]; then
  echo "toolchain workspace が不足しています。先に実行:"
  echo "  ./Scripts/bootstrap_minimal_toolchain_repos.sh $SCHEME $WORKSPACE_DIR"
  exit 1
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "SIL bundle がありません。先に実行:"
  echo "  ./Scripts/prepare_sil_source_bundle.sh"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.20)
project(SwiftSILOptimizerExtract LANGUAGES CXX)

file(GLOB_RECURSE SIL_SOURCES CONFIGURE_DEPENDS
  "$BUNDLE_DIR/lib/*.cpp"
)

if(NOT SIL_SOURCES)
  message(FATAL_ERROR "SIL bundle source が見つかりません: $BUNDLE_DIR/lib")
endif()

add_library(SwiftSILOptimizer STATIC
  $ROOT_DIR/Native/SwiftSILOptimizerAdapter/SwiftSILOptimizerAdapter.cpp
  \${SIL_SOURCES}
)

target_include_directories(SwiftSILOptimizer PRIVATE
  $ROOT_DIR/Native/SwiftSILOptimizerAdapter
  $BUNDLE_DIR/include
  $SWIFT_REPO/include
  $SWIFT_REPO/lib/SIL
  $SWIFT_REPO/lib/SILOptimizer
  $LLVM_REPO/llvm/include
  $LLVM_REPO/clang/include
)

target_compile_features(SwiftSILOptimizer PRIVATE cxx_std_17)
set_target_properties(SwiftSILOptimizer PROPERTIES OUTPUT_NAME SwiftSILOptimizer)
CMAKE

cmake -S "$BUILD_DIR" -B "$BUILD_DIR" -G Ninja
cmake --build "$BUILD_DIR"

cp "$BUILD_DIR/libSwiftSILOptimizer.a" "$OUT_LIB"
echo "生成完了: $OUT_LIB"
