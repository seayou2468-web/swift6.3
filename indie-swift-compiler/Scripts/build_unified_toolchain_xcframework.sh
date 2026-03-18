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
SWIFT_FRONTEND_IOS_BUILD="$WORK_DIR/build/swift-frontend-ios-arm64"
SWIFT_FRONTEND_SIM_BUILD="$WORK_DIR/build/swift-frontend-sim-arm64"
SWIFT_FRONTEND_IOS_INSTALL="$SWIFT_FRONTEND_IOS_BUILD/install"
SWIFT_FRONTEND_SIM_INSTALL="$SWIFT_FRONTEND_SIM_BUILD/install"
SWIFT_FRONTEND_SRC="$WORK_DIR/build/swift-frontend-src"
OUT_DIR="$ROOT_DIR/Artifacts"
UNIFIED_OUT="$OUT_DIR/SwiftToolchainKit.xcframework"
RUNTIME_IOS_LIB=""
RUNTIME_SIM_LIB=""
RUNTIME_IOS_HEADERS=""
RUNTIME_SIM_HEADERS=""

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "必要ツール不足: $1"; exit 1; }
}

require_tool xcodebuild
require_tool cmake
require_tool ninja
require_tool git
require_tool python3

XCODE_VER="$(xcodebuild -version | head -n1 | awk '{print $2}')"
REQUIRED_XCODE_VER="${REQUIRED_XCODE_VERSION:-26.1.1}"
if [[ -n "$REQUIRED_XCODE_VER" && "$XCODE_VER" != "$REQUIRED_XCODE_VER" ]]; then
  echo "エラー: Xcode $REQUIRED_XCODE_VER が必要です。検出: $XCODE_VER"
  echo "回避する場合は REQUIRED_XCODE_VERSION='' を指定してください。"
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

SWIFT_FRONTEND_HOST="$(xcrun --find swift-frontend 2>/dev/null || true)"
if [[ -n "$SWIFT_FRONTEND_HOST" ]]; then
  TOOLCHAIN_ROOT="$(cd "$(dirname "$SWIFT_FRONTEND_HOST")/.." && pwd)"
  if [[ -f "$TOOLCHAIN_ROOT/lib/swift/iphoneos/libswiftCore.a" && -f "$TOOLCHAIN_ROOT/lib/swift/iphonesimulator/libswiftCore.a" ]]; then
    RUNTIME_IOS_LIB="$TOOLCHAIN_ROOT/lib/swift/iphoneos/libswiftCore.a"
    RUNTIME_SIM_LIB="$TOOLCHAIN_ROOT/lib/swift/iphonesimulator/libswiftCore.a"
    RUNTIME_IOS_HEADERS="$TOOLCHAIN_ROOT/lib/swift/iphoneos"
    RUNTIME_SIM_HEADERS="$TOOLCHAIN_ROOT/lib/swift/iphonesimulator"
  fi
fi

rm -rf "$LLVM_IOS_BUILD" "$LLVM_SIM_BUILD" "$SWIFT_FRAMEWORK_BUILD" "$SWIFT_FRONTEND_IOS_BUILD" "$SWIFT_FRONTEND_SIM_BUILD" "$SWIFT_FRONTEND_SRC" "$UNIFIED_OUT"
mkdir -p "$LLVM_IOS_BUILD" "$LLVM_SIM_BUILD" "$SWIFT_FRAMEWORK_BUILD" "$SWIFT_FRONTEND_IOS_BUILD" "$SWIFT_FRONTEND_SIM_BUILD" "$SWIFT_FRONTEND_SRC"

echo "[1/4] Build LLVM/Clang for iOS arm64"
cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_IOS_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_INSTALL_PREFIX="$LLVM_IOS_INSTALL" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF
cmake --build "$LLVM_IOS_BUILD" --target LLVM clang-cpp
cmake --install "$LLVM_IOS_BUILD"

echo "[1/4] Build LLVM/Clang for iOS Simulator arm64"
cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_SIM_BUILD" -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_INSTALL_PREFIX="$LLVM_SIM_INSTALL" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF
cmake --build "$LLVM_SIM_BUILD" --target LLVM clang-cpp
cmake --install "$LLVM_SIM_BUILD"

echo "[2/4] Build swift-frontend adapter static library"
cat > "$SWIFT_FRONTEND_SRC/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.20)
project(SwiftFrontendAdapter LANGUAGES CXX)
add_library(SwiftFrontendAdapter STATIC
  $ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp
)
target_include_directories(SwiftFrontendAdapter PUBLIC
  $ROOT_DIR/Native/SwiftIRGenAdapter
)
target_compile_features(SwiftFrontendAdapter PRIVATE cxx_std_17)
set_target_properties(SwiftFrontendAdapter PROPERTIES OUTPUT_NAME SwiftFrontend)
install(TARGETS SwiftFrontendAdapter ARCHIVE DESTINATION lib)
install(FILES $ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.h DESTINATION include)
CMAKE

cmake -S "$SWIFT_FRONTEND_SRC" -B "$SWIFT_FRONTEND_IOS_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SWIFT_FRONTEND_IOS_INSTALL"
cmake --build "$SWIFT_FRONTEND_IOS_BUILD" --target SwiftFrontendAdapter
cmake --install "$SWIFT_FRONTEND_IOS_BUILD"

cmake -S "$SWIFT_FRONTEND_SRC" -B "$SWIFT_FRONTEND_SIM_BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SWIFT_FRONTEND_SIM_INSTALL"
cmake --build "$SWIFT_FRONTEND_SIM_BUILD" --target SwiftFrontendAdapter
cmake --install "$SWIFT_FRONTEND_SIM_BUILD"

echo "[3/4] Build MiniSwiftCompilerCore framework"
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

echo "[4/4] Create unified xcframework"
XC_ARGS=(
  -create-xcframework
  -framework "$SWIFT_FRAMEWORK_BUILD/ios.xcarchive/Products/Library/Frameworks/MiniSwiftCompilerCore.framework"
  -framework "$SWIFT_FRAMEWORK_BUILD/sim.xcarchive/Products/Library/Frameworks/MiniSwiftCompilerCore.framework"
  -library "$SWIFT_FRONTEND_IOS_INSTALL/lib/libSwiftFrontend.a" -headers "$SWIFT_FRONTEND_IOS_INSTALL/include"
  -library "$SWIFT_FRONTEND_SIM_INSTALL/lib/libSwiftFrontend.a" -headers "$SWIFT_FRONTEND_SIM_INSTALL/include"
  -library "$LLVM_IOS_INSTALL/lib/libLLVM.a" -headers "$LLVM_IOS_INSTALL/include"
  -library "$LLVM_SIM_INSTALL/lib/libLLVM.a" -headers "$LLVM_SIM_INSTALL/include"
  -library "$LLVM_IOS_INSTALL/lib/libclang-cpp.a" -headers "$LLVM_IOS_INSTALL/include"
  -library "$LLVM_SIM_INSTALL/lib/libclang-cpp.a" -headers "$LLVM_SIM_INSTALL/include"
)
if [[ -n "$RUNTIME_IOS_LIB" && -n "$RUNTIME_SIM_LIB" ]]; then
  echo "Swift runtime を unified に追加します"
  XC_ARGS+=(-library "$RUNTIME_IOS_LIB" -headers "$RUNTIME_IOS_HEADERS")
  XC_ARGS+=(-library "$RUNTIME_SIM_LIB" -headers "$RUNTIME_SIM_HEADERS")
else
  echo "警告: Swift runtime static lib が見つからないため unified への追加をスキップします"
fi
XC_ARGS+=(-output "$UNIFIED_OUT")
xcodebuild "${XC_ARGS[@]}"

echo "作成完了: $UNIFIED_OUT"
