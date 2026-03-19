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

NATIVE_BUILD="$BUILD_ROOT/native-host"
IOS_BUILD="$BUILD_ROOT/ios"
SIM_BUILD="$BUILD_ROOT/ios-sim"
IOS_PREFIX="$IOS_BUILD/install"
SIM_PREFIX="$SIM_BUILD/install"
IOS_PACKAGE_DIR="$IOS_BUILD/package"
SIM_PACKAGE_DIR="$SIM_BUILD/package"

rm -rf "$BUILD_ROOT"
mkdir -p "$NATIVE_BUILD" "$IOS_BUILD" "$OUT_DIR"
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
cmake -S "$LLVM_PROJECT/llvm" -B "$IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
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
  -DLLVM_TABLEGEN="$NATIVE_BUILD/bin/llvm-tblgen" \
  -DCLANG_TABLEGEN="$NATIVE_BUILD/bin/clang-tblgen" \
  -DLLVM_NATIVE_BUILD="$NATIVE_BUILD"

build_llvm_clang_libraries "$IOS_BUILD"
cmake --install "$IOS_BUILD"
prepare_llvm_package_artifacts \
  "$IOS_PREFIX" \
  "$IOS_PACKAGE_DIR" \
  "$IOS_PACKAGE_DIR/llvm.a" \
  "$IOS_PACKAGE_DIR/llvm-headers" \
  "$IOS_PACKAGE_DIR/clang-headers"

if [[ "$IOS_DEVICE_ONLY" != "1" ]]; then
  # iOS Simulator
  cmake -S "$LLVM_PROJECT/llvm" -B "$SIM_BUILD" -G Ninja \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
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
    -DLLVM_TABLEGEN="$NATIVE_BUILD/bin/llvm-tblgen" \
    -DCLANG_TABLEGEN="$NATIVE_BUILD/bin/clang-tblgen" \
    -DLLVM_NATIVE_BUILD="$NATIVE_BUILD"

  build_llvm_clang_libraries "$SIM_BUILD"
  cmake --install "$SIM_BUILD"
  prepare_llvm_package_artifacts \
    "$SIM_PREFIX" \
    "$SIM_PACKAGE_DIR" \
    "$SIM_PACKAGE_DIR/llvm.a" \
    "$SIM_PACKAGE_DIR/llvm-headers" \
    "$SIM_PACKAGE_DIR/clang-headers"
fi

LLVM_XC_ARGS=(
  -create-xcframework
  -library "$IOS_PACKAGE_DIR/llvm.a" -headers "$IOS_PACKAGE_DIR/llvm-headers"
)
CLANG_XC_ARGS=(
  -create-xcframework
  -library "$IOS_PREFIX/lib/libclang.dylib" -headers "$IOS_PACKAGE_DIR/clang-headers"
)
if [[ "$IOS_DEVICE_ONLY" != "1" ]]; then
  LLVM_XC_ARGS+=( -library "$SIM_PACKAGE_DIR/llvm.a" -headers "$SIM_PACKAGE_DIR/llvm-headers" )
  CLANG_XC_ARGS+=( -library "$SIM_PREFIX/lib/libclang.dylib" -headers "$SIM_PACKAGE_DIR/clang-headers" )
fi
LLVM_XC_ARGS+=( -output "$OUT_DIR/LLVM.xcframework" )
CLANG_XC_ARGS+=( -output "$OUT_DIR/Clang.xcframework" )

xcodebuild "${LLVM_XC_ARGS[@]}"
xcodebuild "${CLANG_XC_ARGS[@]}"

echo "作成完了:"
echo "  $OUT_DIR/LLVM.xcframework"
echo "  $OUT_DIR/Clang.xcframework"
