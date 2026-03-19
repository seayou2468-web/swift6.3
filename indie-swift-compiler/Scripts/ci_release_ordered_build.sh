#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
TOOLCHAIN_WORKSPACE="${TOOLCHAIN_WORKSPACE:-$ROOT_DIR/.toolchain-workspace}"
OUT_DIR="$ROOT_DIR/Artifacts"
DIST_DIR="$ROOT_DIR/Dist"
LOG_DIR="$DIST_DIR/logs"
DRY_RUN="${CI_DRY_RUN:-0}"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
export NSUnbufferedIO="${NSUnbufferedIO:-YES}"
APPLE_CLEAN_ENV=(
  env
  -u CFLAGS
  -u CXXFLAGS
  -u CPPFLAGS
  -u LDFLAGS
  -u OBJCFLAGS
  -u OBJCXXFLAGS
  -u CMAKE_EXE_LINKER_FLAGS
  -u CMAKE_SHARED_LINKER_FLAGS
  -u CMAKE_MODULE_LINKER_FLAGS
  -u SDKROOT
  -u CMAKE_OSX_SYSROOT
  -u CMAKE_OSX_ARCHITECTURES
  -u MACOSX_DEPLOYMENT_TARGET
  -u IPHONEOS_DEPLOYMENT_TARGET
  -u TVOS_DEPLOYMENT_TARGET
  -u WATCHOS_DEPLOYMENT_TARGET
  -u XROS_DEPLOYMENT_TARGET
  -u SYSROOT
  -u TOOLCHAINS
  -u DEVELOPER_DIR
  -u CPATH
  -u C_INCLUDE_PATH
  -u CPLUS_INCLUDE_PATH
  -u OBJC_INCLUDE_PATH
  -u LIBRARY_PATH
  -u DYLD_LIBRARY_PATH
  -u DYLD_FRAMEWORK_PATH
)

log() {
  echo "[ci-release] $*"
}

run_step() {
  local name="$1"
  shift
  local slug
  slug="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
  local logfile="$LOG_DIR/${slug}.log"
  log "START: $name"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*" > "$logfile"
  else
    if "$@" 2>&1 | tee "$logfile"; then
      :
    else
      log "FAIL : $name"
      return 1
    fi
  fi
  log "DONE : $name (log: $logfile)"
}

require_path() {
  local target="$1"
  if [[ ! -e "$target" ]]; then
    echo "[ci-release] ERROR: required artifact not found: $target" >&2
    return 1
  fi
}

mkdir -p "$OUT_DIR" "$DIST_DIR" "$LOG_DIR"

run_step "Bootstrap minimal toolchain repos" "$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"
run_step "Build standalone LLVM/Clang xcframeworks from update-checkout llvm-project" "${APPLE_CLEAN_ENV[@]}" bash -lc "cd '$ROOT_DIR' && make clean-all LLVM_SRC_DIR='$TOOLCHAIN_WORKSPACE/llvm-project' ROOT='$ROOT_DIR' && make LLVM_SRC_DIR='$TOOLCHAIN_WORKSPACE/llvm-project' ROOT='$ROOT_DIR'"
if [[ "$DRY_RUN" != "1" ]]; then
  mkdir -p "$OUT_DIR"
  rm -rf "$OUT_DIR/LLVM.xcframework" "$OUT_DIR/Clang.xcframework"
  mv "$ROOT_DIR/LLVM.xcframework" "$OUT_DIR/LLVM.xcframework"
  mv "$ROOT_DIR/Clang.xcframework" "$OUT_DIR/Clang.xcframework"
fi

if [[ "$DRY_RUN" != "1" ]]; then
  require_path "$OUT_DIR/LLVM.xcframework"
  require_path "$OUT_DIR/Clang.xcframework"

  MANIFEST="$DIST_DIR/release-manifest.txt"
  {
    echo "scheme=$SCHEME"
    echo "build_id=$BUILD_ID"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git_commit=$(git -C "$ROOT_DIR/.." rev-parse --short HEAD)"
    echo "artifacts:"
    find "$OUT_DIR" -maxdepth 2 -type d -name "*.xcframework" | sort
  } > "$MANIFEST"

  CHECKSUMS="$DIST_DIR/release-checksums.txt"
  : > "$CHECKSUMS"
  while IFS= read -r framework_path; do
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$framework_path" "$DIST_DIR/$(basename "$framework_path").zip"
    shasum -a 256 "$DIST_DIR/$(basename "$framework_path").zip" >> "$CHECKSUMS"
  done < <(find "$OUT_DIR" -maxdepth 2 -type d -name "*.xcframework" | sort)

  ZIP_PATH="$DIST_DIR/LLVM-Clang-${SCHEME//\//-}-${BUILD_ID}.zip"
  /usr/bin/zip -qry "$ZIP_PATH" "$OUT_DIR" "$MANIFEST"
  shasum -a 256 "$ZIP_PATH" >> "$CHECKSUMS"
  log "Release package created: $ZIP_PATH"
fi

log "LLVM/Clang build steps completed"
