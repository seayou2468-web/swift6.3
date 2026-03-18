#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_ROOT="$ROOT_DIR/Vendor/SwiftFrontendExtract"
SOURCE_SET="$ROOT_DIR/Config/irgen-source-set.json"
OUT_FILE="$ROOT_DIR/Config/irgen-dependency-report.json"

python3 "$ROOT_DIR/Tools/analyze_irgen_dependencies.py" \
  --vendor-root "$VENDOR_ROOT" \
  --source-set "$SOURCE_SET" \
  --output "$OUT_FILE"

echo "依存分析レポート: $OUT_FILE"
