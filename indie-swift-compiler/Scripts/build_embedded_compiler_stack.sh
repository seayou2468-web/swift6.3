#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./Scripts/extract_swift_pipeline.sh
make manual-release
swift build -c release

echo "embedded compiler stack build complete"
echo "- extracted compiler sources refreshed from ./swift"
echo "- LLVM.xcframework / Clang.xcframework release zips generated in Release/"
echo "- MiniSwiftCompilerCore built in release mode"
