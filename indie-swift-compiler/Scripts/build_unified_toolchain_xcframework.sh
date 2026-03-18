#!/usr/bin/env bash
set -euo pipefail

# 要件:
# - arm64 のみ
# - Xcode 26.1.1 (xcodebuild -version で検証)
# - Config/minimal-update-checkout-config.json の scheme で指定された
#   llvm-project ブランチを使用
# - ビルド順: llvm/clang -> mini swift compiler -> unified xcframework

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
WORK_DIR="$ROOT_DIR/.build/unified"
TOOLCHAIN_WORKSPACE="$ROOT_DIR/.toolchain-workspace"
LLVM_SRC_DIR="$TOOLCHAIN_WORKSPACE/llvm-project"
LLVM_IOS_BUILD="$WORK_DIR/build/llvm-ios-arm64"
LLVM_SIM_BUILD="$WORK_DIR/build/llvm-sim-arm64"
LLVM_IOS_INSTALL="$LLVM_IOS_BUILD/install"
LLVM_SIM_INSTALL="$LLVM_SIM_BUILD/install"
SWIFT_FRAMEWORK_BUILD="$WORK_DIR/build/swift-compiler-framework"
OUT_DIR="$ROOT_DIR/Artifacts"
UNIFIED_OUT="$OUT_DIR/SwiftToolchainKit.xcframework"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "必要ツール不足: $1"; exit 1; }
}

require_tool xcodebuild
require_tool cmake
require_tool ninja
require_tool git
require_tool python3

XCODE_VER="$(xcodebuild -version | head -n1 | awk '{print $2}')"
if [[ "$XCODE_VER" != "26.1.1" ]]; then
  echo "エラー: Xcode 26.1.1 が必要です。検出: $XCODE_VER"
  exit 1
fi

CONFIG_JSON="$ROOT_DIR/Config/minimal-update-checkout-config.json"
if [[ ! -f "$CONFIG_JSON" ]]; then
  echo "エラー: 最小設定が見つかりません: $CONFIG_JSON"
  exit 1
fi

LLVM_REF="$(python3 - <<PY
import json
cfg=json.load(open('$CONFIG_JSON'))
print(cfg['branch-schemes']['$SCHEME']['repos']['llvm-project'])
PY
)"

echo "llvm-project ref: $LLVM_REF"

mkdir -p "$WORK_DIR/build" "$OUT_DIR"
"$ROOT_DIR/Scripts/bootstrap_minimal_toolchain_repos.sh" "$SCHEME" "$TOOLCHAIN_WORKSPACE"

if [[ ! -d "$LLVM_SRC_DIR/.git" ]]; then
  echo "エラー: llvm-project が見つかりません: $LLVM_SRC_DIR"
  exit 1
fi

rm -rf "$LLVM_IOS_BUILD" "$LLVM_SIM_BUILD" "$SWIFT_FRAMEWORK_BUILD" "$UNIFIED_OUT"
mkdir -p "$LLVM_IOS_BUILD" "$LLVM_SIM_BUILD" "$SWIFT_FRAMEWORK_BUILD"

echo "[1/3] Build LLVM/Clang for iOS arm64"
cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_INSTALL_PREFIX="$LLVM_IOS_INSTALL" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF
cmake --build "$LLVM_IOS_BUILD" --target LLVM clang-cpp
cmake --install "$LLVM_IOS_BUILD"

echo "[1/3] Build LLVM/Clang for iOS Simulator arm64"
cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_SIM_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_INSTALL_PREFIX="$LLVM_SIM_INSTALL" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF
cmake --build "$LLVM_SIM_BUILD" --target LLVM clang-cpp
cmake --install "$LLVM_SIM_BUILD"

echo "[2/3] Build MiniSwiftCompilerCore framework"
xcodebuild archive \
  -scheme MiniSwiftCompilerCore \
  -destination "generic/platform=iOS" \
  -archivePath "$SWIFT_FRAMEWORK_BUILD/ios.xcarchive" \
  -derivedDataPath "$SWIFT_FRAMEWORK_BUILD/DerivedData" \
  -package-path "$ROOT_DIR" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild archive \
  -scheme MiniSwiftCompilerCore \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$SWIFT_FRAMEWORK_BUILD/sim.xcarchive" \
  -derivedDataPath "$SWIFT_FRAMEWORK_BUILD/DerivedData" \
  -package-path "$ROOT_DIR" \
  ARCHS=arm64 \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "[3/3] Create unified xcframework"
xcodebuild -create-xcframework \
  -framework "$SWIFT_FRAMEWORK_BUILD/ios.xcarchive/Products/Library/Frameworks/MiniSwiftCompilerCore.framework" \
  -framework "$SWIFT_FRAMEWORK_BUILD/sim.xcarchive/Products/Library/Frameworks/MiniSwiftCompilerCore.framework" \
  -library "$LLVM_IOS_INSTALL/lib/libLLVM.a" -headers "$LLVM_IOS_INSTALL/include" \
  -library "$LLVM_SIM_INSTALL/lib/libLLVM.a" -headers "$LLVM_SIM_INSTALL/include" \
  -library "$LLVM_IOS_INSTALL/lib/libclang-cpp.a" -headers "$LLVM_IOS_INSTALL/include" \
  -library "$LLVM_SIM_INSTALL/lib/libclang-cpp.a" -headers "$LLVM_SIM_INSTALL/include" \
  -output "$UNIFIED_OUT"

echo "作成完了: $UNIFIED_OUT"
