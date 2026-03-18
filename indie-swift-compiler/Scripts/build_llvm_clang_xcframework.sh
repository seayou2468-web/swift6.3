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

build_llvm_clang_libraries() {
  local build_dir="$1"
  local -a targets=()
  local target_list
  target_list="$(ninja -C "$build_dir" -t targets all 2>/dev/null | awk '{print $1}')"

  if printf '%s\n' "$target_list" | grep -qx 'llvm-libraries'; then
    targets+=(llvm-libraries)
  elif printf '%s\n' "$target_list" | grep -qx 'lib/all'; then
    targets+=(lib/all)
  else
    targets+=(all)
  fi

  if printf '%s\n' "$target_list" | grep -qx 'clang-libraries'; then
    targets+=(clang-libraries)
  elif printf '%s\n' "$target_list" | grep -qx 'clang-cpp'; then
    targets+=(clang-cpp)
  elif printf '%s\n' "$target_list" | grep -qx 'clang'; then
    targets+=(clang)
  fi

  echo "LLVM/Clang build targets: ${targets[*]}"
  cmake --build "$build_dir" --target "${targets[@]}"
}

# iOS Device
cmake -S "$LLVM_PROJECT/llvm" -B "$IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX="$IOS_PREFIX" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_INCLUDE_TOOLS=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF

build_llvm_clang_libraries "$IOS_BUILD"
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
  -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_INCLUDE_TOOLS=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF

build_llvm_clang_libraries "$SIM_BUILD"
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
