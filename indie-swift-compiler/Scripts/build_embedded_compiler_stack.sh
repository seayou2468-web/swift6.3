#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TOOLCHAIN_SCHEME="${TOOLCHAIN_SCHEME:-release/6.3}"
./Scripts/bootstrap_minimal_toolchain_repos.sh "$TOOLCHAIN_SCHEME"

./Scripts/extract_swift_pipeline.sh
make manual-release
swift build -c release

echo "embedded compiler stack build complete"
echo "- minimal update-checkout sync complete for scheme: $TOOLCHAIN_SCHEME"
echo "- extracted compiler sources refreshed from ./swift"
echo "- LLVM.xcframework / Clang.xcframework release zips generated in Release/"
echo "- MiniSwiftCompilerCore built in release mode"
