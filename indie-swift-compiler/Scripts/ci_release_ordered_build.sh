#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
TOOLCHAIN_WORKSPACE="${TOOLCHAIN_WORKSPACE:-$ROOT_DIR/.toolchain-workspace}"
OUT_DIR="$ROOT_DIR/Artifacts"
DIST_DIR="$ROOT_DIR/Dist"
DRY_RUN="${CI_DRY_RUN:-0}"
ALLOW_RUNTIME_FAILURE="${ALLOW_RUNTIME_FAILURE:-1}"

log() {
  echo "[ci-release] $*"
}

run_step() {
  local name="$1"
  shift
  log "START: $name"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
  log "DONE : $name"
}

mkdir -p "$OUT_DIR" "$DIST_DIR"

run_step "Swift Package tests" bash -lc "cd '$ROOT_DIR' && swift test"
run_step "Bootstrap minimal toolchain repos" "$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"
run_step "Build unified toolchain xcframework (ordered: llvm/clang -> swift frontend lib -> core -> unified)" "$ROOT_DIR/Scripts/build_unified_toolchain_xcframework.sh" "$SCHEME"
run_step "Build standalone Swift frontend xcframework" "$ROOT_DIR/Scripts/build_swift_frontend_xcframework.sh"
if [[ "$ALLOW_RUNTIME_FAILURE" == "1" ]]; then
  log "START: Build standalone Swift runtime xcframework (optional)"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"
  elif ! "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"; then
    log "WARN : Swift runtime xcframework build failed (optional step)"
  fi
  log "DONE : Build standalone Swift runtime xcframework (optional)"
else
  run_step "Build standalone Swift runtime xcframework" "$ROOT_DIR/Scripts/build_swift_runtime_xcframework.sh"
fi

if [[ "$DRY_RUN" != "1" ]]; then
  MANIFEST="$DIST_DIR/release-manifest.txt"
  {
    echo "scheme=$SCHEME"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "artifacts:"
    find "$OUT_DIR" -maxdepth 2 -type d -name "*.xcframework" | sort
  } > "$MANIFEST"

  ZIP_PATH="$DIST_DIR/SwiftToolchainKit-${SCHEME//\//-}.zip"
  /usr/bin/zip -qry "$ZIP_PATH" "$OUT_DIR" "$MANIFEST"
  log "Release package created: $ZIP_PATH"
fi

log "All ordered release steps completed"
