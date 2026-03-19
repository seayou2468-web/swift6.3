#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN_WORKSPACE="${TOOLCHAIN_WORKSPACE:-$ROOT_DIR/.toolchain-workspace}"
BUILD_ROOT="$ROOT_DIR/.build/swift-frontend-embedded-stub"
OUT_DIR="$ROOT_DIR/Artifacts/EmbeddedFrontend"
SRC_FILE="$ROOT_DIR/Native/SwiftFrontendEmbedded/SwiftFrontendEmbedded.cpp"
HOST_LIB="$OUT_DIR/libswift_frontend_embedded_host.a"
IOS_LIB="$OUT_DIR/libswift_frontend_embedded_ios.a"
SWIFT_SOURCE_DIR="${SWIFT_FRONTEND_SOURCE_DIR:-$TOOLCHAIN_WORKSPACE/swift}"
LLVM_SOURCE_DIR="${SWIFT_LLVM_SOURCE_DIR:-$TOOLCHAIN_WORKSPACE/llvm-project}"

mkdir -p "$BUILD_ROOT" "$OUT_DIR"

die() {
  echo "エラー: $*" >&2
  exit 1
}

find_first_lib_dir() {
  local libname="$1"
  local search_root="$2"
  local match
  match="$(find "$search_root" -type f -name "$libname" -print 2>/dev/null | head -n 1)"
  if [[ -n "$match" ]]; then
    dirname "$match"
  fi
}

resolve_source_dir() {
  local candidate="$1"
  local required_path="$2"
  if [[ -e "$candidate/$required_path" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

resolve_lib_dir() {
  local explicit_path="$1"
  local fallback_lib="$2"
  if [[ -n "$explicit_path" ]]; then
    [[ -d "$explicit_path" ]] || die "指定されたライブラリディレクトリが見つかりません: $explicit_path"
    printf '%s\n' "$explicit_path"
    return 0
  fi

  local discovered
  discovered="$(find_first_lib_dir "$fallback_lib" "$TOOLCHAIN_WORKSPACE")"
  [[ -n "$discovered" ]] || die "$fallback_lib を TOOLCHAIN_WORKSPACE 配下から検出できません。環境変数で lib dir を指定してください。"
  printf '%s\n' "$discovered"
}

collect_component_libs() {
  local lib_dir="$1"
  FRONTEND_COMPONENT_LIBS=()
  while IFS= read -r lib_path; do
    FRONTEND_COMPONENT_LIBS+=("$lib_path")
  done < <(
    find "$lib_dir" -maxdepth 1 -type f \
      \( -name 'libswift*.a' -o -name 'libclang*.a' -o -name 'libLLVM*.a' \) \
      | sort
  )
  [[ ${#FRONTEND_COMPONENT_LIBS[@]} -gt 0 ]] || die "静的ライブラリが見つかりません: $lib_dir"
}

resolve_include_flags() {
  local target_build_root="$1"
  local swift_source_dir="$2"
  local llvm_source_dir="$3"
  local build_include_dir="$4"
  local extra_dirs="${5:-}"

  INCLUDE_FLAGS=(
    -I"$swift_source_dir/include"
    -I"$llvm_source_dir/llvm/include"
    -I"$llvm_source_dir/clang/include"
  )

  if [[ -d "$build_include_dir" ]]; then
    INCLUDE_FLAGS+=(-I"$build_include_dir")
  fi

  if [[ -d "$target_build_root/include" ]]; then
    INCLUDE_FLAGS+=(-I"$target_build_root/include")
  fi

  if [[ -n "$extra_dirs" ]]; then
    local old_ifs="$IFS"
    IFS=':'
    for dir in $extra_dirs; do
      [[ -n "$dir" ]] || continue
      INCLUDE_FLAGS+=(-I"$dir")
    done
    IFS="$old_ifs"
  fi
}

create_embedded_archive() {
  local sdk="$1"
  local build_name="$2"
  local component_lib_dir="$3"
  local output_lib="$4"
  local generated_include_dir="$5"
  local extra_include_dirs="$6"
  local object_file="$BUILD_ROOT/${build_name}.o"

  collect_component_libs "$component_lib_dir"
  resolve_include_flags "$component_lib_dir/.." "$SWIFT_SOURCE_DIR" "$LLVM_SOURCE_DIR" "$generated_include_dir" "$extra_include_dirs"

  xcrun -sdk "$sdk" clang++ \
    -std=c++17 \
    -arch arm64 \
    -c "$SRC_FILE" \
    "${INCLUDE_FLAGS[@]}" \
    -o "$object_file"

  libtool -static -o "$output_lib" "$object_file" "${FRONTEND_COMPONENT_LIBS[@]}"
}

resolve_source_dir "$SWIFT_SOURCE_DIR" "include/swift/FrontendTool/FrontendTool.h" >/dev/null \
  || die "Swift source/include が見つかりません。SWIFT_FRONTEND_SOURCE_DIR を指定してください。"
resolve_source_dir "$LLVM_SOURCE_DIR" "llvm/include/llvm/ADT/SmallVector.h" >/dev/null \
  || die "LLVM source/include が見つかりません。SWIFT_LLVM_SOURCE_DIR を指定してください。"

HOST_FRONTEND_LIB_DIR="$(resolve_lib_dir "${SWIFT_FRONTEND_EMBEDDED_HOST_LIB_DIR:-}" 'libswiftFrontendTool.a')"
IOS_FRONTEND_LIB_DIR="$(resolve_lib_dir "${SWIFT_FRONTEND_EMBEDDED_IOS_LIB_DIR:-}" 'libswiftFrontendTool.a')"
HOST_GENERATED_INCLUDE_DIR="${SWIFT_FRONTEND_EMBEDDED_HOST_GENERATED_INCLUDE_DIR:-}"
IOS_GENERATED_INCLUDE_DIR="${SWIFT_FRONTEND_EMBEDDED_IOS_GENERATED_INCLUDE_DIR:-}"
HOST_EXTRA_INCLUDE_DIRS="${SWIFT_FRONTEND_EMBEDDED_HOST_EXTRA_INCLUDE_DIRS:-}"
IOS_EXTRA_INCLUDE_DIRS="${SWIFT_FRONTEND_EMBEDDED_IOS_EXTRA_INCLUDE_DIRS:-}"

create_embedded_archive \
  macosx \
  host \
  "$HOST_FRONTEND_LIB_DIR" \
  "$HOST_LIB" \
  "$HOST_GENERATED_INCLUDE_DIR" \
  "$HOST_EXTRA_INCLUDE_DIRS"

create_embedded_archive \
  iphoneos \
  ios \
  "$IOS_FRONTEND_LIB_DIR" \
  "$IOS_LIB" \
  "$IOS_GENERATED_INCLUDE_DIR" \
  "$IOS_EXTRA_INCLUDE_DIRS"

echo "SWIFT_FRONTEND_EMBEDDED_LIB_IOS=$IOS_LIB"
