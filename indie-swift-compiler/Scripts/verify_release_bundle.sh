#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${1:-$ROOT_DIR/Dist}"
OUT_DIR="${2:-$ROOT_DIR/Artifacts}"

MANIFEST="$DIST_DIR/release-manifest.txt"
CHECKSUMS="$DIST_DIR/release-checksums.txt"

if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest が見つかりません: $MANIFEST"
  exit 1
fi
if [[ ! -f "$CHECKSUMS" ]]; then
  echo "checksums が見つかりません: $CHECKSUMS"
  exit 1
fi

grep -q '^scheme=' "$MANIFEST"
grep -q '^build_id=' "$MANIFEST"
grep -q '^git_commit=' "$MANIFEST"

while IFS= read -r framework; do
  [[ -z "$framework" ]] && continue
  [[ "$framework" == artifacts:* ]] && continue
  [[ "$framework" == scheme=* ]] && continue
  [[ "$framework" == build_id=* ]] && continue
  [[ "$framework" == date=* ]] && continue
  [[ "$framework" == git_commit=* ]] && continue

  if [[ "$framework" == *.xcframework ]]; then
    if [[ ! -d "$framework" ]]; then
      echo "manifest記載のxcframeworkが存在しません: $framework"
      exit 1
    fi
  fi
done < "$MANIFEST"

(
  cd "$DIST_DIR"
  shasum -a 256 -c "$CHECKSUMS"
)

if [[ ! -d "$OUT_DIR/SwiftToolchainKit.xcframework" ]]; then
  echo "必須成果物不足: $OUT_DIR/SwiftToolchainKit.xcframework"
  exit 1
fi
if [[ ! -d "$OUT_DIR/SwiftFrontend.xcframework" ]]; then
  echo "必須成果物不足: $OUT_DIR/SwiftFrontend.xcframework"
  exit 1
fi

echo "release bundle 検証OK"
