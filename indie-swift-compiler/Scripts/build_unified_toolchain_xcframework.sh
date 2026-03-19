#!/usr/bin/env bash
set -euo pipefail

# 要件:
# - arm64 のみ
# - Xcode 26.1.1 (xcodebuild -version で検証)
# - Config/minimal-update-checkout-config.json の scheme で指定された
#   llvm-project ブランチを使用
# - ビルド順: llvm/clang -> mini swift compiler -> unified xcframework

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
WORK_DIR="$ROOT_DIR/.build/unified"
TOOLCHAIN_WORKSPACE="$ROOT_DIR/.toolchain-workspace"
LLVM_SRC_DIR="$TOOLCHAIN_WORKSPACE/llvm-project"
LLVM_NATIVE_BUILD="$WORK_DIR/build/llvm-native-host"
LLVM_IOS_BUILD="$WORK_DIR/build/llvm-ios-arm64"
LLVM_IOS_INSTALL="$LLVM_IOS_BUILD/install"
SWIFT_FRAMEWORK_BUILD="$WORK_DIR/build/swift-compiler-framework"
SWIFT_FRONTEND_IOS_BUILD="$WORK_DIR/build/swift-frontend-ios-arm64"
SWIFT_FRONTEND_IOS_INSTALL="$SWIFT_FRONTEND_IOS_BUILD/install"
SWIFT_FRONTEND_SRC="$WORK_DIR/build/swift-frontend-src"
LLVM_PACKAGE_DIR="$WORK_DIR/build/llvm-package-ios"
LLVM_COMBINED_ARCHIVE="$LLVM_PACKAGE_DIR/llvm.a"
LLVM_HEADERS_DIR="$LLVM_PACKAGE_DIR/llvm-headers"
CLANG_HEADERS_DIR="$LLVM_PACKAGE_DIR/clang-headers"
OUT_DIR="$ROOT_DIR/Artifacts"
UNIFIED_OUT="$OUT_DIR/SwiftToolchainKit.xcframework"
EMBEDDED_IOS_LIB="${SWIFT_FRONTEND_EMBEDDED_LIB_IOS:-}"
SILOPT_IOS_LIB="${SWIFT_SILOPTIMIZER_EMBEDDED_LIB_IOS:-}"
RUNTIME_IOS_LIB="${SWIFT_RUNTIME_IOS_LIB:-}"
RUNTIME_IOS_HEADERS="${SWIFT_RUNTIME_IOS_HEADERS:-}"
APPLE_ARCH="${APPLE_ARCH:-arm64}"
LLVM_ARCH="${LLVM_ARCH:-AArch64}"
APPLE_LINKER_CMAKE_FLAGS=()
NATIVE_LLVM_CMAKE_FLAGS=()

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "必要ツール不足: $1"; exit 1; }
}

require_tool xcodebuild
require_tool cmake
require_tool ninja
require_tool git
require_tool python3
require_tool libtool
require_tool nm

clear_inherited_apple_build_flags() {
  unset CFLAGS
  unset CXXFLAGS
  unset CPPFLAGS
  unset LDFLAGS
  unset OBJCFLAGS
  unset OBJCXXFLAGS
  unset CMAKE_EXE_LINKER_FLAGS
  unset CMAKE_SHARED_LINKER_FLAGS
  unset CMAKE_MODULE_LINKER_FLAGS
}

configure_apple_linker_cmake_flags() {
  APPLE_LINKER_CMAKE_FLAGS=(
    "-DCMAKE_EXE_LINKER_FLAGS=-Wl,-dead_strip"
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-dead_strip"
    "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,-dead_strip"
  )
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

build_native_llvm_tablegen_tools() {
  local llvm_source_dir="$1"
  local build_dir="$2"

  cmake -S "$llvm_source_dir" -B "$build_dir" -G Ninja \
    -DLLVM_ENABLE_PROJECTS="clang" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_TARGETS_TO_BUILD="Native" \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_BUILD_TOOLS=ON \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_BUILD_UTILS=ON \
    -DLLVM_INCLUDE_TOOLS=ON \
    -DLLVM_INCLUDE_UTILS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLVM_ENABLE_ZLIB=OFF \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_THREADS=ON \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_RTTI=ON \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF

  cmake --build "$build_dir" --target llvm-tblgen clang-tblgen

  if [[ ! -x "$build_dir/bin/llvm-tblgen" || ! -x "$build_dir/bin/clang-tblgen" ]]; then
    echo "エラー: native tblgen tools の生成に失敗しました: $build_dir/bin"
    exit 1
  fi

  NATIVE_LLVM_CMAKE_FLAGS=(
    "-DLLVM_TABLEGEN=$build_dir/bin/llvm-tblgen"
    "-DCLANG_TABLEGEN=$build_dir/bin/clang-tblgen"
    "-DLLVM_NATIVE_TOOL_DIR=$build_dir/bin"
    "-DLLVM_NATIVE_BUILD=$build_dir"
  )
}

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
    cmake --build "$build_dir" --target "${bootstrap_targets[@]}"
  fi

  local -a llvm_candidates=(llvm-libraries lib/all all)
  local -a clang_candidates=(clang-libraries clang-cpp clang "")
  local -a lld_candidates=(lld "")
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

      for lld_t in "${lld_candidates[@]}"; do
        if [[ -n "$lld_t" ]] && ! printf '%s\n' "$target_list" | grep -qx "$lld_t"; then
          continue
        fi

        build_args=(--target "$llvm_t")
        if [[ -n "$clang_t" ]]; then
          build_args+=("$clang_t")
        fi
        if [[ -n "$lld_t" ]]; then
          build_args+=("$lld_t")
        fi

        tried=$((tried+1))
        echo "LLVM/Clang/LLD build attempt #$tried: ${build_args[*]}"
        if cmake --build "$build_dir" "${build_args[@]}"; then
          return 0
        fi

        echo "WARN: build attempt failed. trying next fallback targets..."
      done
    done
  done

  echo "WARN: no target combination succeeded, fallback to plain 'cmake --build'"
  cmake --build "$build_dir"
}


XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>/dev/null || true)"
XCODE_VER="$(printf '%s\n' "$XCODE_VERSION_OUTPUT" | awk 'NR==1 { print $2 }')"
REQUIRED_XCODE_VER="${REQUIRED_XCODE_VERSION:-26.1.1}"
if [[ -n "$REQUIRED_XCODE_VER" && "$XCODE_VER" != "$REQUIRED_XCODE_VER" ]]; then
  echo "エラー: Xcode $REQUIRED_XCODE_VER が必要です。検出: $XCODE_VER"
  echo "回避する場合は REQUIRED_XCODE_VERSION='' を指定してください。"
  exit 1
fi

CONFIG_JSON="$ROOT_DIR/Config/minimal-update-checkout-config.json"
if [[ ! -f "$CONFIG_JSON" ]]; then
  echo "エラー: 最小設定が見つかりません: $CONFIG_JSON"
  exit 1
fi

LLVM_REF="$(python3 - <<PY
import json
cfg=json.load(open('$CONFIG_JSON'))
print(cfg['branch-schemes']['$SCHEME']['repos']['llvm-project'])
PY
)"

echo "llvm-project ref: $LLVM_REF"

mkdir -p "$WORK_DIR/build" "$OUT_DIR"
"$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"

if [[ ! -d "$LLVM_SRC_DIR/.git" ]]; then
  echo "エラー: llvm-project が見つかりません: $LLVM_SRC_DIR"
  exit 1
fi

if [[ -n "$RUNTIME_IOS_LIB" && -z "$RUNTIME_IOS_HEADERS" ]]; then
  RUNTIME_IOS_HEADERS="$(dirname "$RUNTIME_IOS_LIB")"
fi

if [[ -z "$EMBEDDED_IOS_LIB" ]]; then
  echo "エラー: 実機向け実体同梱が必須です。"
  echo "SWIFT_FRONTEND_EMBEDDED_LIB_IOS を指定してください。"
  exit 1
fi
if [[ ! -f "$EMBEDDED_IOS_LIB" ]]; then
  echo "エラー: 指定された iOS 実機向け実体ライブラリが見つかりません。"
  echo "  iOS: $EMBEDDED_IOS_LIB"
  exit 1
fi
if [[ -n "$RUNTIME_IOS_LIB" && ! -f "$RUNTIME_IOS_LIB" ]]; then
  echo "エラー: 指定された Swift runtime static lib(iOS) が見つかりません。"
  echo "  iOS runtime: $RUNTIME_IOS_LIB"
  exit 1
fi
if [[ -n "$RUNTIME_IOS_LIB" && ! -d "$RUNTIME_IOS_HEADERS" ]]; then
  echo "エラー: 指定された Swift runtime headers(iOS) が見つかりません。"
  echo "  iOS runtime headers: $RUNTIME_IOS_HEADERS"
  exit 1
fi
rm -rf "$LLVM_NATIVE_BUILD" "$LLVM_IOS_BUILD" "$SWIFT_FRAMEWORK_BUILD" "$SWIFT_FRONTEND_IOS_BUILD" "$SWIFT_FRONTEND_SRC" "$LLVM_PACKAGE_DIR" "$UNIFIED_OUT"
mkdir -p "$LLVM_NATIVE_BUILD" "$LLVM_IOS_BUILD" "$SWIFT_FRAMEWORK_BUILD" "$SWIFT_FRONTEND_IOS_BUILD" "$SWIFT_FRONTEND_SRC"

echo "[1/4] Build LLVM/Clang for iOS arm64"
clear_inherited_apple_build_flags
configure_apple_linker_cmake_flags
build_native_llvm_tablegen_tools "$LLVM_SRC_DIR/llvm" "$LLVM_NATIVE_BUILD"
cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES="$APPLE_ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_INSTALL_PREFIX="$LLVM_IOS_INSTALL" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DLLVM_TARGETS_TO_BUILD="$LLVM_ARCH" \
  -DLLVM_TARGET_ARCH="$LLVM_ARCH" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$APPLE_ARCH-apple-ios" \
  -DCOMPILER_RT_ENABLE_IOS=FALSE \
  -DCOMPILER_RT_ENABLE_WATCHOS=FALSE \
  -DCOMPILER_RT_ENABLE_TVOS=FALSE \
  -DCOMPILER_RT_ENABLE_XROS=FALSE \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
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
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  "${NATIVE_LLVM_CMAKE_FLAGS[@]}" \
  "${APPLE_LINKER_CMAKE_FLAGS[@]}"
build_llvm_clang_libraries "$LLVM_IOS_BUILD"
cmake --install "$LLVM_IOS_BUILD"
prepare_llvm_package_artifacts \
  "$LLVM_IOS_INSTALL" \
  "$LLVM_PACKAGE_DIR" \
  "$LLVM_COMBINED_ARCHIVE" \
  "$LLVM_HEADERS_DIR" \
  "$CLANG_HEADERS_DIR"



echo "[2/4] Build swift-frontend adapter static library"
cat > "$SWIFT_FRONTEND_SRC/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.20)
project(SwiftFrontendAdapter LANGUAGES CXX)
add_library(SwiftFrontendAdapter STATIC
  $ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp
)
target_include_directories(SwiftFrontendAdapter PUBLIC
  $ROOT_DIR/Native/SwiftIRGenAdapter
)
target_compile_features(SwiftFrontendAdapter PRIVATE cxx_std_17)
set_target_properties(SwiftFrontendAdapter PROPERTIES OUTPUT_NAME SwiftFrontend)
install(TARGETS SwiftFrontendAdapter ARCHIVE DESTINATION lib)
install(FILES $ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.h DESTINATION include)
CMAKE

cmake -S "$SWIFT_FRONTEND_SRC" -B "$SWIFT_FRONTEND_IOS_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES="$APPLE_ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SWIFT_FRONTEND_IOS_INSTALL"
cmake --build "$SWIFT_FRONTEND_IOS_BUILD" --target SwiftFrontendAdapter
cmake --install "$SWIFT_FRONTEND_IOS_BUILD"
mv "$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontend.a" "$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontendAdapter.a"
libtool -static \
  -o "$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontend.a" \
  "$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontendAdapter.a" \
  "$EMBEDDED_IOS_LIB"

libs_to_check=("$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontend.a")
for lib in "${libs_to_check[@]}"; do
  if ! nm -gU "$lib" 2>/dev/null | grep -q "swift_frontend_embedded_compile"; then
    echo "エラー: $lib に swift_frontend_embedded_compile が含まれていません。"
    exit 1
  fi
done

echo "[3/4] Build MiniSwiftCompilerCore framework"
xcodebuild archive \
  -scheme MiniSwiftCompilerCore \
  -destination "generic/platform=iOS" \
  -archivePath "$SWIFT_FRAMEWORK_BUILD/ios.xcarchive" \
  -derivedDataPath "$SWIFT_FRAMEWORK_BUILD/DerivedData" \
  -package-path "$ROOT_DIR" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "[4/4] Create unified xcframework"
XC_ARGS=(
  -create-xcframework
  -framework "$SWIFT_FRAMEWORK_BUILD/ios.xcarchive/Products/Library/Frameworks/MiniSwiftCompilerCore.framework"
  -library "$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontend.a" -headers "$SWIFT_FRONTEND_IOS_INSTALL/include"
  -library "$LLVM_COMBINED_ARCHIVE" -headers "$LLVM_HEADERS_DIR"
  -library "$LLVM_IOS_INSTALL/lib/libclang.dylib" -headers "$CLANG_HEADERS_DIR"
)
if [[ -n "$SILOPT_IOS_LIB" ]]; then
  if [[ ! -f "$SILOPT_IOS_LIB" ]]; then
    echo "エラー: 指定された SILOptimizer ライブラリが見つかりません。"
    echo "  iOS: $SILOPT_IOS_LIB"
    exit 1
  fi
  echo "Swift SILOptimizer を unified に追加します"
  XC_ARGS+=(-library "$SILOPT_IOS_LIB" -headers "$ROOT_DIR/Native/SwiftSILOptimizerAdapter")
else
  echo "警告: SILOptimizer static lib が未指定のため unified への追加をスキップします"
fi
if [[ -n "$RUNTIME_IOS_LIB" ]]; then
  echo "Swift runtime(iOS) を unified に追加します"
  XC_ARGS+=(-library "$RUNTIME_IOS_LIB" -headers "$RUNTIME_IOS_HEADERS")
else
  echo "警告: Swift runtime static lib(iOS) が未指定のため unified への追加をスキップします"
fi
XC_ARGS+=(-output "$UNIFIED_OUT")
xcodebuild "${XC_ARGS[@]}"

echo "作成完了: $UNIFIED_OUT"
