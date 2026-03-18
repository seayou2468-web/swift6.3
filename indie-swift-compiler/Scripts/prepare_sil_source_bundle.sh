#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_ROOT="$ROOT_DIR/Vendor/SwiftFrontendExtract"
SOURCE_SET="$ROOT_DIR/Config/sil-source-set.json"
OUT_DIR="$ROOT_DIR/Generated/SwiftSILExtract"

python3 "$ROOT_DIR/Tools/create_irgen_bundle.py" \
  --vendor-root "$VENDOR_ROOT" \
  --source-set "$SOURCE_SET" \
  --output "$OUT_DIR"

echo "SIL最小ソースバンドル: $OUT_DIR"
