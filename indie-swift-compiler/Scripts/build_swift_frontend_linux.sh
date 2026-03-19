#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/swift-frontend-linux"
OUT_DIR="${LOCAL_SWIFT_FRONTEND_LINUX_OUT_DIR:-$ROOT_DIR/.build/local/swift-frontend-linux}"
HEADERS_DIR="$ROOT_DIR/Native/SwiftIRGenAdapter"
SRC_FILE="$ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp"
EMBEDDED_LINUX_LIB="${SWIFT_FRONTEND_EMBEDDED_LIB_LINUX:-}"
TOOLCHAIN_WORKSPACE="${TOOLCHAIN_WORKSPACE:-$ROOT_DIR/.toolchain-workspace}"
SCHEME="${LINUX_TOOLCHAIN_SCHEME:-release/6.3}"
AUTO_BOOTSTRAP_TOOLCHAIN="${AUTO_BOOTSTRAP_TOOLCHAIN:-1}"
LLVM_PROJECT="${LINUX_LLVM_PROJECT_PATH:-$TOOLCHAIN_WORKSPACE/llvm-project}"
BUILD_LINUX_LLVM="${BUILD_LINUX_LLVM:-1}"
LLVM_BUILD="$BUILD_ROOT/llvm"
LLVM_PREFIX="$OUT_DIR/llvm"
LINUX_BUILD="$BUILD_ROOT/linux"
LINUX_PREFIX="$LINUX_BUILD/install"
ADAPTER_LIB="$LINUX_PREFIX/lib/libSwiftFrontendAdapter.a"
UNIFIED_LIB="$OUT_DIR/lib/libSwiftFrontend.a"
INCLUDE_OUT="$OUT_DIR/include"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "必要ツール不足: $1"; exit 1; }
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
    cmake --build "$build_dir" --target "${bootstrap_targets[@]}"
  fi

  local -a llvm_candidates=(llvm-libraries lib/all all)
  local -a clang_candidates=(clang-libraries clang-cpp clang "")
  local -a lld_candidates=(lld "")
  local -a build_args=()

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
        if cmake --build "$build_dir" "${build_args[@]}"; then
          return 0
        fi
      done
    done
  done

  cmake --build "$build_dir"
}

bootstrap_toolchain_if_needed() {
  if [[ "$AUTO_BOOTSTRAP_TOOLCHAIN" != "1" ]]; then
    return 0
  fi

  if [[ -d "$LLVM_PROJECT/llvm" ]]; then
    return 0
  fi

  echo "llvm-project が見つからないため最小ツールチェーン取得を実行します: $TOOLCHAIN_WORKSPACE (scheme=$SCHEME)"
  "$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"
}

build_local_llvm_if_requested() {
  if [[ "$BUILD_LINUX_LLVM" != "1" ]]; then
    echo "BUILD_LINUX_LLVM=0 のため LLVM/Clang Linux ローカルビルドはスキップします"
    return 0
  fi

  bootstrap_toolchain_if_needed

  if [[ ! -d "$LLVM_PROJECT/llvm" ]]; then
    echo "エラー: Linux 用 LLVM ソースが見つかりません: $LLVM_PROJECT/llvm"
    echo "LINUX_LLVM_PROJECT_PATH を指定するか BUILD_LINUX_LLVM=0 を設定してください。"
    exit 1
  fi

  rm -rf "$LLVM_BUILD" "$LLVM_PREFIX"
  mkdir -p "$LLVM_BUILD" "$LLVM_PREFIX"

  cmake -S "$LLVM_PROJECT/llvm" -B "$LLVM_BUILD" -G Ninja \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$LLVM_PREFIX" \
    -DLLVM_TARGETS_TO_BUILD="Native;X86;AArch64" \
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

  build_llvm_clang_libraries "$LLVM_BUILD"
  cmake --build "$LLVM_BUILD" --target llvm-as llc clang lld
  cmake --install "$LLVM_BUILD"
}

require_tool cmake
require_tool ninja
require_tool ar
require_tool ranlib
require_tool nm
require_tool c++
require_tool python3
require_tool git

rm -rf "$LINUX_BUILD" "$OUT_DIR/lib" "$OUT_DIR/include"
mkdir -p "$LINUX_BUILD" "$OUT_DIR/lib" "$INCLUDE_OUT"

if [[ -z "$EMBEDDED_LINUX_LIB" ]]; then
  echo "エラー: Linux 用の実体同梱が必須です。"
  echo "SWIFT_FRONTEND_EMBEDDED_LIB_LINUX を指定してください。"
  exit 1
fi

if [[ ! -f "$EMBEDDED_LINUX_LIB" ]]; then
  echo "エラー: 指定された Linux 実体ライブラリが見つかりません: $EMBEDDED_LINUX_LIB"
  exit 1
fi

build_local_llvm_if_requested

cat > "$BUILD_ROOT/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.20)
project(SwiftFrontendAdapterLinux LANGUAGES CXX)

add_library(SwiftFrontendAdapter STATIC
  $SRC_FILE
)

target_include_directories(SwiftFrontendAdapter PUBLIC
  $HEADERS_DIR
)

target_compile_features(SwiftFrontendAdapter PRIVATE cxx_std_17)
set_target_properties(SwiftFrontendAdapter PROPERTIES OUTPUT_NAME SwiftFrontendAdapter)

install(TARGETS SwiftFrontendAdapter ARCHIVE DESTINATION lib)
install(FILES $HEADERS_DIR/SwiftIRGenAdapter.h DESTINATION include)
CMAKE

cmake -S "$BUILD_ROOT" -B "$LINUX_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LINUX_PREFIX"
cmake --build "$LINUX_BUILD" --target SwiftFrontendAdapter
cmake --install "$LINUX_BUILD"

cp "$LINUX_PREFIX/include/SwiftIRGenAdapter.h" "$INCLUDE_OUT/"
cp "$ADAPTER_LIB" "$UNIFIED_LIB"
ar -q "$UNIFIED_LIB" "$EMBEDDED_LINUX_LIB"
ranlib "$UNIFIED_LIB"

if ! nm -g "$UNIFIED_LIB" 2>/dev/null | grep -q "swift_frontend_embedded_compile"; then
  echo "エラー: $UNIFIED_LIB に swift_frontend_embedded_compile が含まれていません。"
  exit 1
fi

echo "ローカルビルド完了: $UNIFIED_LIB"
echo "ヘッダ出力: $INCLUDE_OUT/SwiftIRGenAdapter.h"
if [[ "$BUILD_LINUX_LLVM" == "1" ]]; then
  echo "LLVM/Clang 出力: $LLVM_PREFIX"
fi
