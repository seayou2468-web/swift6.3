#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/swift-frontend-embedded-stub"
OUT_DIR="$ROOT_DIR/Artifacts/EmbeddedFrontend"
SRC_FILE="$BUILD_ROOT/swift_frontend_embedded_stub.cpp"
IOS_LIB="$OUT_DIR/libswift_frontend_embedded_ios.a"
SIM_LIB="$OUT_DIR/libswift_frontend_embedded_sim.a"

mkdir -p "$BUILD_ROOT" "$OUT_DIR"

cat > "$SRC_FILE" <<'CPP'
extern "C" int swift_frontend_embedded_compile(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path) {
  (void)swift_source;
  (void)target_triple;
  (void)sdk_path;
  (void)module_name;
  (void)out_ll_path;
  return -200;
}
CPP

xcrun -sdk iphoneos clang++ -std=c++17 -arch arm64 -c "$SRC_FILE" -o "$BUILD_ROOT/ios.o"
libtool -static -o "$IOS_LIB" "$BUILD_ROOT/ios.o"

xcrun -sdk iphonesimulator clang++ -std=c++17 -arch arm64 -c "$SRC_FILE" -o "$BUILD_ROOT/sim.o"
libtool -static -o "$SIM_LIB" "$BUILD_ROOT/sim.o"

echo "SWIFT_FRONTEND_EMBEDDED_LIB_IOS=$IOS_LIB"
echo "SWIFT_FRONTEND_EMBEDDED_LIB_SIM=$SIM_LIB"
