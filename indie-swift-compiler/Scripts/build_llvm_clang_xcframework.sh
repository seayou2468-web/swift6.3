#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "使い方: $0 <llvm-project-path>"
  echo "例: $0 ~/src/llvm-project"
  exit 1
fi

LLVM_PROJECT="$(cd "$1" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/apple_build_common.sh"
BUILD_ROOT="$ROOT_DIR/.build/llvm-clang"
OUT_DIR="$ROOT_DIR/Artifacts"

NATIVE_BUILD="$BUILD_ROOT/native-host"
IOS_BUILD="$BUILD_ROOT/ios"
IOS_PREFIX="$IOS_BUILD/install"
IOS_PACKAGE_DIR="$IOS_BUILD/package"

require_darwin_arm64_host
clear_inherited_apple_build_env
configure_host_apple_cmake_flags
configure_optional_compiler_launcher_flags

rm -rf "$BUILD_ROOT"
mkdir -p "$NATIVE_BUILD" "$IOS_BUILD" "$OUT_DIR"

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
  if printf '%s\n' "$target_list" | grep -qx 'clang-headers'; then
    bootstrap_targets+=(clang-headers)
  fi
  if [[ ${#bootstrap_targets[@]} -gt 0 ]]; then
    echo "Prebuild bootstrap targets: ${bootstrap_targets[*]}"
    cmake_build "$build_dir" --target "${bootstrap_targets[@]}"
  fi

  local llvm_t
  local clang_t
  local lld_t
  local -a build_args=()
  llvm_t="$(pick_first_available_target "$target_list" llvm-libraries lib/all all)" || llvm_t="all"
  clang_t="$(pick_first_available_target "$target_list" clang-libraries clang-cpp clang __EMPTY__)" || clang_t=""
  lld_t="$(pick_first_available_target "$target_list" lld __EMPTY__)" || lld_t=""

  build_args=(--target "$llvm_t")
  if [[ -n "$clang_t" ]]; then
    build_args+=("$clang_t")
  fi
  if [[ -n "$lld_t" ]]; then
    build_args+=("$lld_t")
  fi

  echo "LLVM/Clang/LLD build targets: ${build_args[*]}"
  if cmake_build "$build_dir" "${build_args[@]}"; then
    return 0
  fi

  echo "WARN: no target combination succeeded, fallback to plain 'cmake --build'"
  cmake_build "$build_dir"
}

build_native_llvm_tablegen_tools() {
  local llvm_source_dir="$1"
  local build_dir="$2"
  local -a cmake_args=(
    -S "$llvm_source_dir"
    -B "$build_dir"
    -G Ninja
    -DLLVM_ENABLE_PROJECTS="clang"
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_TARGETS_TO_BUILD="$LLVM_ARCH"
    -DCLANG_INCLUDE_TESTS=OFF
    -DCLANG_BUILD_TOOLS=ON
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF
    -DCLANG_ENABLE_ARCMT=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_BUILD_TOOLS=ON
    -DLLVM_BUILD_UTILS=ON
    -DLLVM_INCLUDE_TOOLS=ON
    -DLLVM_INCLUDE_UTILS=ON
    -DBUILD_SHARED_LIBS=OFF
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_THREADS=ON
    -DLLVM_ENABLE_UNWIND_TABLES=OFF
    -DLLVM_ENABLE_EH=OFF
    -DLLVM_ENABLE_RTTI=ON
    -DLLVM_ENABLE_TERMINFO=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
  )
  cmake_args+=("${APPLE_HOST_STAGE_CMAKE_FLAGS[@]}")
  if [[ ${#CMAKE_LAUNCHER_FLAGS[@]} -gt 0 ]]; then
    cmake_args+=("${CMAKE_LAUNCHER_FLAGS[@]}")
  fi
  cmake "${cmake_args[@]}"

  cmake_build "$build_dir" --target llvm-tblgen clang-tblgen

  if [[ ! -x "$build_dir/bin/llvm-tblgen" || ! -x "$build_dir/bin/clang-tblgen" ]]; then
    echo "エラー: native tblgen tools の生成に失敗しました: $build_dir/bin"
    exit 1
  fi
}

prepare_llvm_package_artifacts() {
  local install_prefix="$1"
  local package_dir="$2"
  local archive_path="$3"
  local llvm_headers_dir="$4"
  local clang_headers_dir="$5"
  local clang_dylib="$install_prefix/lib/libclang.dylib"
  local -a llvm_inputs=()

  shopt -s nullglob
  llvm_inputs=(
    "$install_prefix"/lib/libLLVM*.a
    "$install_prefix"/lib/libclang*.a
    "$install_prefix"/lib/liblld*.a
  )
  shopt -u nullglob

  if [[ ${#llvm_inputs[@]} -eq 0 ]]; then
    echo "エラー: LLVM/Clang/LLD static library が見つかりません: $install_prefix/lib"
    exit 1
  fi
  if [[ ! -f "$clang_dylib" ]]; then
    echo "エラー: libclang.dylib が見つかりません: $clang_dylib"
    exit 1
  fi
  if [[ ! -d "$install_prefix/include/clang-c" ]]; then
    echo "エラー: clang-c headers が見つかりません: $install_prefix/include/clang-c"
    exit 1
  fi

  rm -rf "$package_dir"
  mkdir -p "$llvm_headers_dir" "$clang_headers_dir"
  libtool -static -o "$archive_path" "${llvm_inputs[@]}"
  cp -R "$install_prefix/include/." "$llvm_headers_dir/"
  rm -rf "$llvm_headers_dir/clang-c"
  cp -R "$install_prefix/include/clang-c/." "$clang_headers_dir/"
}

# iOS Device
build_native_llvm_tablegen_tools "$LLVM_PROJECT/llvm" "$NATIVE_BUILD"
configure_cross_apple_cmake_flags iphoneos
ios_cmake_args=(
  -S "$LLVM_PROJECT/llvm"
  -B "$IOS_BUILD"
  -G Ninja
  -DLLVM_ENABLE_PROJECTS="clang;lld"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
  -DCMAKE_INSTALL_PREFIX="$IOS_PREFIX"
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  -DLLVM_TARGETS_TO_BUILD="$LLVM_ARCH"
  -DCOMPILER_RT_ENABLE_IOS=FALSE
  -DCOMPILER_RT_ENABLE_WATCHOS=FALSE
  -DCOMPILER_RT_ENABLE_TVOS=FALSE
  -DCOMPILER_RT_ENABLE_XROS=FALSE
  -DCLANG_INCLUDE_TESTS=OFF
  -DCLANG_BUILD_TOOLS=OFF
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF
  -DCLANG_ENABLE_ARCMT=OFF
  -DLLVM_INCLUDE_DOCS=OFF
  -DLLVM_INCLUDE_EXAMPLES=OFF
  -DLLVM_BUILD_TOOLS=OFF
  -DLLVM_BUILD_UTILS=OFF
  -DLLVM_INCLUDE_TOOLS=OFF
  -DLLVM_INCLUDE_UTILS=OFF
  -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON
  -DBUILD_SHARED_LIBS=OFF
  -DLLVM_ENABLE_ZLIB=OFF
  -DLLVM_ENABLE_ZSTD=OFF
  -DLLVM_ENABLE_THREADS=ON
  -DLLVM_ENABLE_UNWIND_TABLES=OFF
  -DLLVM_ENABLE_EH=OFF
  -DLLVM_ENABLE_RTTI=ON
  -DLLVM_ENABLE_TERMINFO=OFF
  -DLLVM_ENABLE_LIBXML2=OFF
  -DLLVM_INCLUDE_TESTS=OFF
  -DLLVM_INCLUDE_BENCHMARKS=OFF
)
ios_cmake_args+=("${APPLE_CROSS_STAGE_CMAKE_FLAGS[@]}")
if [[ ${#CMAKE_LAUNCHER_FLAGS[@]} -gt 0 ]]; then
  ios_cmake_args+=("${CMAKE_LAUNCHER_FLAGS[@]}")
fi
ios_cmake_args+=(
  -DLLVM_TABLEGEN="$NATIVE_BUILD/bin/llvm-tblgen"
  -DCLANG_TABLEGEN="$NATIVE_BUILD/bin/clang-tblgen"
  -DLLVM_NATIVE_TOOL_DIR="$NATIVE_BUILD/bin"
  -DLLVM_NATIVE_BUILD="$NATIVE_BUILD"
)
cmake "${ios_cmake_args[@]}"

build_llvm_clang_libraries "$IOS_BUILD"
cmake --install "$IOS_BUILD"
prepare_llvm_package_artifacts \
  "$IOS_PREFIX" \
  "$IOS_PACKAGE_DIR" \
  "$IOS_PACKAGE_DIR/llvm.a" \
  "$IOS_PACKAGE_DIR/llvm-headers" \
  "$IOS_PACKAGE_DIR/clang-headers"

LLVM_XC_ARGS=(
  -create-xcframework
  -library "$IOS_PACKAGE_DIR/llvm.a" -headers "$IOS_PACKAGE_DIR/llvm-headers"
)
CLANG_XC_ARGS=(
  -create-xcframework
  -library "$IOS_PREFIX/lib/libclang.dylib" -headers "$IOS_PACKAGE_DIR/clang-headers"
)
LLVM_XC_ARGS+=( -output "$OUT_DIR/LLVM.xcframework" )
CLANG_XC_ARGS+=( -output "$OUT_DIR/Clang.xcframework" )

xcodebuild_safe "${LLVM_XC_ARGS[@]}"
xcodebuild_safe "${CLANG_XC_ARGS[@]}"

echo "作成完了:"
echo "  $OUT_DIR/LLVM.xcframework"
echo "  $OUT_DIR/Clang.xcframework"
