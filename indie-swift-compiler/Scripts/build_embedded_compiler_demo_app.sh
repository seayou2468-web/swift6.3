#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="$ROOT_DIR/Demo/EmbeddedCompilerIDE"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build the demo app"
  exit 1
fi

cd "$DEMO_DIR"
xcodegen generate
xcodebuild \
  -project EmbeddedCompilerIDE.xcodeproj \
  -scheme EmbeddedCompilerIDE \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
