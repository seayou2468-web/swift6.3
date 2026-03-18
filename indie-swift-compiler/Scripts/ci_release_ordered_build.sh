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
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
export NSUnbufferedIO="${NSUnbufferedIO:-YES}"

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
    if "$@" >"$logfile" 2>&1; then
      :
    else
      log "FAIL : $name"
      echo "----- BEGIN LOG: $logfile -----"
      cat "$logfile"
      echo "----- END LOG: $logfile -----"
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
run_step "Build unified toolchain xcframework (ordered: llvm/clang -> swift frontend lib -> core -> unified)" "$ROOT_DIR/Scripts/build_unified_toolchain_xcframework.sh" "$SCHEME"
run_step "Build standalone Swift frontend xcframework" "$ROOT_DIR/Scripts/build_swift_frontend_xcframework.sh"
if [[ "$ALLOW_RUNTIME_FAILURE" == "1" ]]; then
  if ! run_step "Build standalone Swift runtime xcframework optional" "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"; then
    log "WARN : Swift runtime xcframework build failed (optional step)"
  fi
else
  run_step "Build standalone Swift runtime xcframework" "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"
fi

if [[ "$DRY_RUN" != "1" ]]; then
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
