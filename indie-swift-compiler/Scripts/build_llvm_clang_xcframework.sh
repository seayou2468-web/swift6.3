#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "使い方: $0 <llvm-project-path>"
  echo "例: $0 ~/src/llvm-project"
  exit 1
fi

LLVM_PROJECT="$(cd "$1" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/llvm-clang"
OUT_DIR="$ROOT_DIR/Artifacts"

IOS_BUILD="$BUILD_ROOT/ios"
SIM_BUILD="$BUILD_ROOT/ios-sim"
IOS_PREFIX="$IOS_BUILD/install"
SIM_PREFIX="$SIM_BUILD/install"

rm -rf "$BUILD_ROOT"
mkdir -p "$IOS_BUILD" "$SIM_BUILD" "$OUT_DIR"

# iOS Device
cmake -S "$LLVM_PROJECT/llvm" -B "$IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX="$IOS_PREFIX" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF

cmake --build "$IOS_BUILD" --target LLVM clang-cpp
cmake --install "$IOS_BUILD"

# iOS Simulator
cmake -S "$LLVM_PROJECT/llvm" -B "$SIM_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_INSTALL_PREFIX="$SIM_PREFIX" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF

cmake --build "$SIM_BUILD" --target LLVM clang-cpp
cmake --install "$SIM_BUILD"

xcodebuild -create-xcframework \
  -library "$IOS_PREFIX/lib/libLLVM.a" -headers "$IOS_PREFIX/include" \
  -library "$SIM_PREFIX/lib/libLLVM.a" -headers "$SIM_PREFIX/include" \
  -output "$OUT_DIR/LLVM.xcframework"

xcodebuild -create-xcframework \
  -library "$IOS_PREFIX/lib/libclang-cpp.a" -headers "$IOS_PREFIX/include" \
  -library "$SIM_PREFIX/lib/libclang-cpp.a" -headers "$SIM_PREFIX/include" \
  -output "$OUT_DIR/Clang.xcframework"

echo "作成完了:"
echo "  $OUT_DIR/LLVM.xcframework"
echo "  $OUT_DIR/Clang.xcframework"
