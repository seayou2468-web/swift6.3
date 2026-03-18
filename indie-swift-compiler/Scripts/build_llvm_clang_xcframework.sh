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
IOS_DEVICE_ONLY="${IOS_DEVICE_ONLY:-1}"

IOS_BUILD="$BUILD_ROOT/ios"
SIM_BUILD="$BUILD_ROOT/ios-sim"
IOS_PREFIX="$IOS_BUILD/install"
SIM_PREFIX="$SIM_BUILD/install"

rm -rf "$BUILD_ROOT"
mkdir -p "$IOS_BUILD" "$OUT_DIR"
if [[ "$IOS_DEVICE_ONLY" != "1" ]]; then
  mkdir -p "$SIM_BUILD"
fi

build_llvm_clang_libraries() {
  local build_dir="$1"
  local target_list
  target_list="$(ninja -C "$build_dir" -t targets all 2>/dev/null | awk '{print $1}')"
  local -a bootstrap_targets=()
  if printf '%s\n' "$target_list" | grep -qx 'llvm-config'; then
    bootstrap_targets+=(llvm-config)
  fi
  if printf '%s\n' "$target_list" | grep -qx 'clang-resource-headers'; then
    bootstrap_targets+=(clang-resource-headers)
  fi
  if [[ ${#bootstrap_targets[@]} -gt 0 ]]; then
    echo "Prebuild bootstrap targets: ${bootstrap_targets[*]}"
    cmake --build "$build_dir" --target "${bootstrap_targets[@]}"
  fi

  local -a llvm_candidates=(llvm-libraries lib/all all)
  local -a clang_candidates=(clang-libraries clang-cpp clang "")
  local -a build_args=()
  local tried=0

  for llvm_t in "${llvm_candidates[@]}"; do
    if [[ "$llvm_t" != "all" ]] && ! printf '%s\n' "$target_list" | grep -qx "$llvm_t"; then
      continue
    fi

    for clang_t in "${clang_candidates[@]}"; do
      if [[ -n "$clang_t" ]] && [[ "$clang_t" != "clang" ]] && ! printf '%s\n' "$target_list" | grep -qx "$clang_t"; then
        continue
      fi
      if [[ "$clang_t" == "clang" ]] && ! printf '%s\n' "$target_list" | grep -qx 'clang'; then
        continue
      fi

      build_args=(--target "$llvm_t")
      if [[ -n "$clang_t" ]]; then
        build_args+=("$clang_t")
      fi

      tried=$((tried+1))
      echo "LLVM/Clang build attempt #$tried: ${build_args[*]}"
      if cmake --build "$build_dir" "${build_args[@]}"; then
        return 0
      fi

      echo "WARN: build attempt failed. trying next fallback targets..."
    done
  done

  echo "WARN: no target combination succeeded, fallback to plain 'cmake --build'"
  cmake --build "$build_dir"
}

# iOS Device
cmake -S "$LLVM_PROJECT/llvm" -B "$IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX="$IOS_PREFIX" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86" \
  -DCOMPILER_RT_ENABLE_IOS=FALSE \
  -DCOMPILER_RT_ENABLE_WATCHOS=FALSE \
  -DCOMPILER_RT_ENABLE_TVOS=FALSE \
  -DCOMPILER_RT_ENABLE_XROS=FALSE \
  -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
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

if [[ "$IOS_DEVICE_ONLY" != "1" ]]; then
  # iOS Simulator
  cmake -S "$LLVM_PROJECT/llvm" -B "$SIM_BUILD" -G Ninja \
    -DLLVM_ENABLE_PROJECTS="clang" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_INSTALL_PREFIX="$SIM_PREFIX" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86" \
    -DCOMPILER_RT_ENABLE_IOS=FALSE \
    -DCOMPILER_RT_ENABLE_WATCHOS=FALSE \
    -DCOMPILER_RT_ENABLE_TVOS=FALSE \
    -DCOMPILER_RT_ENABLE_XROS=FALSE \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
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
fi

LLVM_XC_ARGS=(
  -create-xcframework
  -library "$IOS_PREFIX/lib/libLLVM.a" -headers "$IOS_PREFIX/include"
)
CLANG_XC_ARGS=(
  -create-xcframework
  -library "$IOS_PREFIX/lib/libclang-cpp.a" -headers "$IOS_PREFIX/include"
)
if [[ "$IOS_DEVICE_ONLY" != "1" ]]; then
  LLVM_XC_ARGS+=( -library "$SIM_PREFIX/lib/libLLVM.a" -headers "$SIM_PREFIX/include" )
  CLANG_XC_ARGS+=( -library "$SIM_PREFIX/lib/libclang-cpp.a" -headers "$SIM_PREFIX/include" )
fi
LLVM_XC_ARGS+=( -output "$OUT_DIR/LLVM.xcframework" )
CLANG_XC_ARGS+=( -output "$OUT_DIR/Clang.xcframework" )

xcodebuild "${LLVM_XC_ARGS[@]}"
xcodebuild "${CLANG_XC_ARGS[@]}"

echo "作成完了:"
echo "  $OUT_DIR/LLVM.xcframework"
echo "  $OUT_DIR/Clang.xcframework"
