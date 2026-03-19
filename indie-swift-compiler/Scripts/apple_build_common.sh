#!/usr/bin/env bash

APPLE_ARCH="${APPLE_ARCH:-arm64}"
LLVM_ARCH="${LLVM_ARCH:-AArch64}"
HOST_OS="${HOST_OS:-$(uname -s)}"
HOST_ARCH="${HOST_ARCH:-$(uname -m)}"
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)}"
declare -a CMAKE_LAUNCHER_FLAGS=()

require_darwin_arm64_host() {
  if [[ "$HOST_OS" != "Darwin" ]]; then
    echo "エラー: Apple build は macOS ホストでのみ実行できます。検出: $HOST_OS"
    exit 1
  fi
  if [[ "$HOST_ARCH" != "$APPLE_ARCH" ]]; then
    echo "エラー: Apple build のホストアーキテクチャは $APPLE_ARCH のみ対応です。検出: $HOST_ARCH"
    exit 1
  fi
}

clear_inherited_apple_build_env() {
  unset CFLAGS
  unset CXXFLAGS
  unset CPPFLAGS
  unset LDFLAGS
  unset OBJCFLAGS
  unset OBJCXXFLAGS
  unset CMAKE_EXE_LINKER_FLAGS
  unset CMAKE_SHARED_LINKER_FLAGS
  unset CMAKE_MODULE_LINKER_FLAGS
  unset SDKROOT
  unset CMAKE_OSX_SYSROOT
  unset CMAKE_OSX_ARCHITECTURES
  unset MACOSX_DEPLOYMENT_TARGET
  unset IPHONEOS_DEPLOYMENT_TARGET
  unset TVOS_DEPLOYMENT_TARGET
  unset WATCHOS_DEPLOYMENT_TARGET
  unset XROS_DEPLOYMENT_TARGET
}

configure_optional_compiler_launcher_flags() {
  CMAKE_LAUNCHER_FLAGS=()
  if command -v ccache >/dev/null 2>&1; then
    export CCACHE_DIR="${CCACHE_DIR:-$(pwd)/.build/ccache}"
    export CCACHE_BASEDIR="${CCACHE_BASEDIR:-$(pwd)}"
    export CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK:-content}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"
    mkdir -p "$CCACHE_DIR"
    CMAKE_LAUNCHER_FLAGS=(
      "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
      "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    )
    echo "ccache enabled: dir=$CCACHE_DIR"
  fi
}

cmake_build() {
  if cmake --build "$@" --parallel "$BUILD_JOBS"; then
    return 0
  fi
  if [[ "$BUILD_JOBS" -gt 1 ]]; then
    echo "WARN: parallel build failed, retrying serial build for stability..."
    cmake --build "$@" --parallel 1
    return $?
  fi
  return 1
}

xcodebuild_safe() {
  if xcodebuild "$@" -jobs "$BUILD_JOBS"; then
    return 0
  fi
  if [[ "$BUILD_JOBS" -gt 1 ]]; then
    echo "WARN: xcodebuild failed with parallel jobs, retrying serial build..."
    xcodebuild "$@" -jobs 1
    return $?
  fi
  return 1
}

pick_first_available_target() {
  local target_list="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "$candidate" == "__EMPTY__" ]]; then
      echo ""
      return 0
    fi
    if printf '%s\n' "$target_list" | grep -qx "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}
