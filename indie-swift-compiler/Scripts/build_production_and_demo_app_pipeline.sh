#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
TOOLCHAIN_SCHEME="${TOOLCHAIN_SCHEME:-release/6.3}"

ensure_path() {
  local path="$1"
  local label="$2"
  if [ ! -e "$path" ]; then
    echo "[ERROR] missing ${label}: ${path}" >&2
    exit 1
  fi
}

echo "[1/6] syncing minimal update-checkout repos for indie compiler"
./Scripts/bootstrap_minimal_toolchain_repos.sh "$TOOLCHAIN_SCHEME"

echo "[2/6] extracting swift frontend pipeline"
./Scripts/extract_swift_pipeline.sh

echo "[3/6] building LLVM/Clang xcframework artifacts"
make release-llvm-clang
ensure_path "LLVM.xcframework" "LLVM xcframework"
ensure_path "Clang.xcframework" "Clang xcframework"
ensure_path "Release/LLVM-21.1.6-iphoneos.zip" "LLVM release zip"
ensure_path "Release/Clang-21.1.6-iphoneos.zip" "Clang release zip"

echo "[4/6] building MiniSwiftCompilerCore products"
swift build -c release --product MiniSwiftCompilerCore --product MiniSwiftCompilerCoreStatic
ensure_path ".build" "swift build output directory"

echo "[5/6] building demo app target with production artifacts available"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] demo app target requires macOS/SwiftUI (current: $(uname -s))" >&2
  exit 1
fi
swift build -c release --target EmbeddedCompilerIDE
DEMO_APP_BIN="$(find .build -type f -name EmbeddedCompilerIDE | head -n 1 || true)"
if [ -z "$DEMO_APP_BIN" ]; then
  echo "[ERROR] could not find EmbeddedCompilerIDE binary under .build" >&2
  exit 1
fi

echo "[6/6] staging demo-app build inputs"
STAGE_DIR="Release/DemoAppBuildInputs"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R LLVM.xcframework "$STAGE_DIR/"
cp -R Clang.xcframework "$STAGE_DIR/"
cp "$DEMO_APP_BIN" "$STAGE_DIR/EmbeddedCompilerIDE"

echo "production-and-demo pipeline complete"
echo "- minimal update-checkout sync complete for scheme: $TOOLCHAIN_SCHEME"
echo "- LLVM/Clang xcframeworks built and verified"
echo "- MiniSwiftCompilerCore built in release mode"
echo "- EmbeddedCompilerIDE built in release mode"
echo "- staged build inputs at $STAGE_DIR"
