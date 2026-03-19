#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/swift-frontend-embedded-stub"
OUT_DIR="$ROOT_DIR/Artifacts/EmbeddedFrontend"
SRC_FILE="$ROOT_DIR/Native/SwiftFrontendEmbedded/SwiftFrontendEmbedded.cpp"
HOST_LIB="$OUT_DIR/libswift_frontend_embedded_host.a"
IOS_LIB="$OUT_DIR/libswift_frontend_embedded_ios.a"

mkdir -p "$BUILD_ROOT" "$OUT_DIR"

xcrun -sdk macosx clang++ -std=c++17 -arch arm64 -c "$SRC_FILE" -o "$BUILD_ROOT/host.o"
libtool -static -o "$HOST_LIB" "$BUILD_ROOT/host.o"

xcrun -sdk iphoneos clang++ -std=c++17 -arch arm64 -c "$SRC_FILE" -o "$BUILD_ROOT/ios.o"
libtool -static -o "$IOS_LIB" "$BUILD_ROOT/ios.o"

echo "SWIFT_FRONTEND_EMBEDDED_LIB_IOS=$IOS_LIB"
