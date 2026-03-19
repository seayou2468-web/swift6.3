#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/apple_build_common.sh"
SCHEME="${1:-release/6.3}"
WORK_DIR="$ROOT_DIR/.build/compiler-rt"
TOOLCHAIN_WORKSPACE="${TOOLCHAIN_WORKSPACE:-$ROOT_DIR/.toolchain-workspace}"
LLVM_SRC_DIR="$TOOLCHAIN_WORKSPACE/llvm-project"
OUT_DIR="$ROOT_DIR/Artifacts"
OUT_XC="$OUT_DIR/CompilerRT.xcframework"

NATIVE_BUILD="$WORK_DIR/native-host"
IOS_BUILD="$WORK_DIR/ios"
IOS_INSTALL="$IOS_BUILD/install"
IOS_DYLIB_HEADERS="$WORK_DIR/dylib-headers/ios"
IOS_DYLIB_DIR="$WORK_DIR/dylibs/ios"

require_tool() { command -v "$1" >/dev/null 2>&1 || { echo "必要ツール不足: $1"; exit 1; }; }
require_tool cmake
require_tool ninja
require_tool xcodebuild
require_tool libtool

require_darwin_arm64_host
clear_inherited_apple_build_env
configure_host_apple_cmake_flags
configure_optional_compiler_launcher_flags

mkdir -p "$WORK_DIR" "$OUT_DIR"
"$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"

if [[ ! -d "$LLVM_SRC_DIR/llvm" ]]; then
  echo "エラー: llvm-project が見つかりません: $LLVM_SRC_DIR"
  exit 1
fi

rm -rf "$NATIVE_BUILD" "$IOS_BUILD" "$IOS_DYLIB_HEADERS" "$IOS_DYLIB_DIR" "$OUT_XC"
mkdir -p "$NATIVE_BUILD" "$IOS_BUILD" "$IOS_DYLIB_HEADERS" "$IOS_DYLIB_DIR"

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
}

configure_compiler_rt() {
  local build_dir="$1"
  local install_dir="$2"
  local sysroot="$3"
  local archs="$4"
  configure_cross_apple_cmake_flags "$sysroot"
  local -a cmake_args=(
    -S "$LLVM_SRC_DIR/llvm"
    -B "$build_dir"
    -G Ninja
    -DLLVM_ENABLE_PROJECTS="clang"
    -DLLVM_ENABLE_RUNTIMES="compiler-rt"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    -DCMAKE_INSTALL_PREFIX="$install_dir"
    -DLLVM_TARGETS_TO_BUILD="$LLVM_ARCH"
    -DLLVM_BUILD_TOOLS=OFF
    -DLLVM_INCLUDE_TOOLS=OFF
    -DLLVM_BUILD_UTILS=OFF
    -DLLVM_INCLUDE_UTILS=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DCLANG_INCLUDE_TESTS=OFF
    -DCLANG_BUILD_TOOLS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DCOMPILER_RT_ENABLE_IOS=TRUE
    -DCOMPILER_RT_ENABLE_WATCHOS=FALSE
    -DCOMPILER_RT_ENABLE_TVOS=FALSE
    -DCOMPILER_RT_ENABLE_XROS=FALSE
  )
  cmake_args+=("${APPLE_CROSS_STAGE_CMAKE_FLAGS[@]}")
  cmake_args+=(
    "-DLLVM_TABLEGEN=$NATIVE_BUILD/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=$NATIVE_BUILD/bin/clang-tblgen"
    "-DLLVM_NATIVE_TOOL_DIR=$NATIVE_BUILD/bin"
    "-DLLVM_NATIVE_BUILD=$NATIVE_BUILD"
  )
  if [[ ${#CMAKE_LAUNCHER_FLAGS[@]} -gt 0 ]]; then
    cmake_args+=("${CMAKE_LAUNCHER_FLAGS[@]}")
  fi
  cmake "${cmake_args[@]}"
}

build_compiler_rt() {
  local build_dir="$1"
  local target_list
  target_list="$(ninja -C "$build_dir" -t targets all 2>/dev/null | awk '{print $1}')"

  local -a pre=()
  if printf '%s\n' "$target_list" | grep -qx 'llvm-config'; then pre+=(llvm-config); fi
  if printf '%s\n' "$target_list" | grep -qx 'clang-resource-headers'; then pre+=(clang-resource-headers); fi
  if [[ ${#pre[@]} -gt 0 ]]; then
    cmake_build "$build_dir" --target "${pre[@]}"
  fi

  for t in compiler-rt runtimes all; do
    if printf '%s\n' "$target_list" | grep -qx "$t" || [[ "$t" == "all" ]]; then
      if cmake_build "$build_dir" --target "$t"; then
        return 0
      fi
    fi
  done
  cmake_build "$build_dir"
}

collect_compiler_rt_dylibs() {
  local install_dir="$1"
  local out_dir="$2"
  local -a dylibs=()
  while IFS= read -r dylib_path; do
    dylibs+=("$dylib_path")
  done < <(find "$install_dir" -type f -name 'libclang_rt*.dylib' | sort)

  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  for dylib_path in "${dylibs[@]}"; do
    cp "$dylib_path" "$out_dir/"
  done
}

build_native_llvm_tablegen_tools "$LLVM_SRC_DIR/llvm" "$NATIVE_BUILD"
configure_compiler_rt "$IOS_BUILD" "$IOS_INSTALL" iphoneos "$APPLE_ARCH"
build_compiler_rt "$IOS_BUILD"
cmake --install "$IOS_BUILD"
cat > "$IOS_DYLIB_HEADERS/CompilerRT.h" <<'HDR'
#pragma once
// Collected compiler-rt dylibs for iOS device.
HDR
collect_compiler_rt_dylibs "$IOS_INSTALL" "$IOS_DYLIB_DIR"

DYNAMIC_XC_ARGS=( -create-xcframework )
for dylib_path in "$IOS_DYLIB_DIR"/libclang_rt*.dylib; do
  if [[ -f "$dylib_path" ]]; then
    DYNAMIC_XC_ARGS+=( -library "$dylib_path" -headers "$IOS_DYLIB_HEADERS" )
  fi
done

if [[ ${#DYNAMIC_XC_ARGS[@]} -gt 1 ]]; then
  DYNAMIC_XC_ARGS+=( -output "$OUT_XC" )
  xcodebuild_safe "${DYNAMIC_XC_ARGS[@]}"
  echo "作成完了: $OUT_XC"
else
  echo "エラー: libclang_rt.dylib が見つからなかったため CompilerRT.xcframework を生成できません"
  exit 1
fi
