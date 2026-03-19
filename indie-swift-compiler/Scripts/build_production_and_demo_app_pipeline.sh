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
bash ./Scripts/bootstrap_minimal_toolchain_repos.sh "$TOOLCHAIN_SCHEME"

echo "[2/6] extracting swift frontend pipeline"
bash ./Scripts/extract_swift_pipeline.sh

echo "[3/6] building LLVM/Clang xcframework artifacts"
make release-llvm-clang
ensure_path "LLVM.xcframework" "LLVM xcframework"
ensure_path "Clang.xcframework" "Clang xcframework"
ensure_path "Release/LLVM-21.1.6-iphoneos.zip" "LLVM release zip"
ensure_path "Release/Clang-21.1.6-iphoneos.zip" "Clang release zip"

echo "[4/6] building MiniSwiftCompilerCore products"
swift build -c release --product MiniSwiftCompilerCore
ensure_path ".build" "swift build output directory"

echo "[5/6] building demo app target with production artifacts available"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] iOS demo app target requires macOS/Xcode (current: $(uname -s))" >&2
  exit 1
fi
DERIVED_DATA_PATH="$ROOT_DIR/.build/EmbeddedCompilerIDE-iOS"
rm -rf "$DERIVED_DATA_PATH"
xcodebuild \
  -project "Demo/EmbeddedCompilerIDE-iOS/EmbeddedCompilerIDE.xcodeproj" \
  -scheme "EmbeddedCompilerIDE" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build
DEMO_APP_BIN="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/EmbeddedCompilerIDE.app"
if [ -z "$DEMO_APP_BIN" ]; then
  echo "[ERROR] could not find EmbeddedCompilerIDE.app under DerivedData" >&2
  exit 1
fi
if [ ! -d "$DEMO_APP_BIN" ]; then
  echo "[ERROR] expected demo app bundle was not produced: $DEMO_APP_BIN" >&2
  exit 1
fi

echo "[6/6] staging demo-app build inputs"
STAGE_DIR="Release/DemoAppBuildInputs"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R LLVM.xcframework "$STAGE_DIR/"
cp -R Clang.xcframework "$STAGE_DIR/"
cp -R "$DEMO_APP_BIN" "$STAGE_DIR/EmbeddedCompilerIDE.app"

echo "production-and-demo pipeline complete"
echo "- minimal update-checkout sync complete for scheme: $TOOLCHAIN_SCHEME"
echo "- LLVM/Clang xcframeworks built and verified"
echo "- MiniSwiftCompilerCore built in release mode"
echo "- EmbeddedCompilerIDE iOS device app built in release mode"
echo "- staged build inputs at $STAGE_DIR"
