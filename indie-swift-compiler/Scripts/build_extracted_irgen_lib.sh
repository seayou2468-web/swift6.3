#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="${1:-$ROOT_DIR/.toolchain-workspace}"
SCHEME="${2:-release/6.3}"

SWIFT_REPO="$WORKSPACE_DIR/swift"
LLVM_REPO="$WORKSPACE_DIR/llvm-project"
BUNDLE_DIR="$ROOT_DIR/Generated/SwiftIRGenExtract"
BUILD_DIR="$ROOT_DIR/.build/irgen-adapter"
OUT_LIB="$BUILD_DIR/libSwiftIRGenAdapter.a"

if [[ ! -d "$SWIFT_REPO" || ! -d "$LLVM_REPO" ]]; then
  echo "toolchain workspace が不足しています。先に実行:"
  echo "  ./Scripts/bootstrap_minimal_toolchain_repos.sh $SCHEME $WORKSPACE_DIR"
  exit 1
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "IRGen bundle がありません。先に実行:"
  echo "  ./Scripts/prepare_irgen_source_bundle.sh"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.20)
project(SwiftIRGenAdapter LANGUAGES CXX)

add_library(SwiftIRGenAdapter STATIC
  $ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp
)

target_include_directories(SwiftIRGenAdapter PRIVATE
  $ROOT_DIR/Native/SwiftIRGenAdapter
  $BUNDLE_DIR/include
  $SWIFT_REPO/include
  $SWIFT_REPO/lib/IRGen
  $LLVM_REPO/llvm/include
  $LLVM_REPO/clang/include
)

target_compile_features(SwiftIRGenAdapter PRIVATE cxx_std_17)
CMAKE

cmake -S "$BUILD_DIR" -B "$BUILD_DIR" -G Ninja
cmake --build "$BUILD_DIR"

cp "$BUILD_DIR/libSwiftIRGenAdapter.a" "$OUT_LIB"
echo "生成完了: $OUT_LIB"
