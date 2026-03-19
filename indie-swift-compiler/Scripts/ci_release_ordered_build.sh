#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
TOOLCHAIN_WORKSPACE="${TOOLCHAIN_WORKSPACE:-$ROOT_DIR/.toolchain-workspace}"
OUT_DIR="$ROOT_DIR/Artifacts"
DIST_DIR="$ROOT_DIR/Dist"
LOG_DIR="$DIST_DIR/logs"
DRY_RUN="${CI_DRY_RUN:-0}"
ALLOW_RUNTIME_FAILURE="${ALLOW_RUNTIME_FAILURE:-1}"
VERIFY_IOS_EMBEDDING_STRICT="${VERIFY_IOS_EMBEDDING_STRICT:-0}"
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

run_step "Swift Package tests" bash -lc "cd '$ROOT_DIR' && swift test"
run_step "Bootstrap minimal toolchain repos" "$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"

if [[ -z "${SWIFT_FRONTEND_EMBEDDED_LIB_IOS:-}" ]]; then
  EMBEDDED_ENV="$LOG_DIR/embedded-frontend.env"
  run_step "Build embedded frontend stub libs" "${APPLE_CLEAN_ENV[@]}" bash -lc "cd '$ROOT_DIR' && ./Scripts/build_swift_frontend_embedded_stub.sh > '$EMBEDDED_ENV'"
  if [[ "$DRY_RUN" == "1" ]]; then
    export SWIFT_FRONTEND_EMBEDDED_LIB_IOS="/dry-run/libswift_frontend_embedded_ios.a"
  else
    # shellcheck disable=SC1090
    source "$EMBEDDED_ENV"
    export SWIFT_FRONTEND_EMBEDDED_LIB_IOS
  fi
fi

run_step "Build unified toolchain xcframework (ordered: llvm/clang -> swift frontend lib -> core -> unified)" "${APPLE_CLEAN_ENV[@]}" "$ROOT_DIR/Scripts/build_unified_toolchain_xcframework.sh" "$SCHEME"
run_step "Build standalone compiler-rt xcframework" "${APPLE_CLEAN_ENV[@]}" "$ROOT_DIR/Scripts/build_compiler_rt_xcframework.sh" "$SCHEME"
run_step "Build standalone Swift frontend xcframework" "${APPLE_CLEAN_ENV[@]}" "$ROOT_DIR/Scripts/build_swift_frontend_xcframework.sh"
if [[ "$ALLOW_RUNTIME_FAILURE" == "1" ]]; then
  if ! run_step "Build standalone Swift runtime xcframework optional" "${APPLE_CLEAN_ENV[@]}" "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"; then
    log "WARN : Swift runtime xcframework build failed (optional step)"
  fi
else
  run_step "Build standalone Swift runtime xcframework" "${APPLE_CLEAN_ENV[@]}" "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"
fi

if [[ "$DRY_RUN" != "1" ]]; then
  run_step "Verify iOS embedding readiness (frontend/runtime)" env VERIFY_IOS_EMBEDDING_STRICT="$VERIFY_IOS_EMBEDDING_STRICT" "$ROOT_DIR/Scripts/verify_ios_embedding_readiness.sh" "$OUT_DIR"

  require_path "$OUT_DIR/SwiftToolchainKit.xcframework"
  require_path "$OUT_DIR/SwiftFrontend.xcframework"

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

  ZIP_PATH="$DIST_DIR/SwiftToolchainKit-${SCHEME//\//-}-${BUILD_ID}.zip"
  /usr/bin/zip -qry "$ZIP_PATH" "$OUT_DIR" "$MANIFEST"
  shasum -a 256 "$ZIP_PATH" >> "$CHECKSUMS"
  log "Release package created: $ZIP_PATH"

  "$ROOT_DIR/Scripts/verify_release_bundle.sh" "$DIST_DIR" "$OUT_DIR"
fi

log "All ordered release steps completed"
