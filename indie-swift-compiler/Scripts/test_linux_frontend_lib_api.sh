#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/linux-lib-api-test"
mkdir -p "$BUILD_DIR"

CXX="${CXX:-g++}"

$CXX -std=c++17 -fPIC -shared \
  "$ROOT_DIR/Native/SwiftIRGenAdapter/SwiftIRGenAdapter.cpp" \
  -I"$ROOT_DIR/Native/SwiftIRGenAdapter" \
  -o "$BUILD_DIR/libSwiftFrontendAdapter.so"

cat > "$BUILD_DIR/harness.cpp" <<'CPP'
#include "SwiftIRGenAdapter.h"
#include <fstream>
#include <iostream>
#include <string>

extern "C" int swift_frontend_embedded_compile(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path) {
  (void)swift_source;
  (void)target_triple;
  (void)sdk_path;

  std::ofstream out(out_ll_path);
  if (!out.is_open()) {
    return -101;
  }
  out << "; ModuleID = '" << module_name << "'\\n";
  out << "define i64 @testEntry() {\\n";
  out << "entry:\\n";
  out << "  ret i64 42\\n";
  out << "}\\n";
  out.close();
  return 0;
}

int main() {
  const char *source = "public func testEntry() -> Int { return 42 }\n";
  const char *module = "LinuxFrontendLibAPITest";
  const char *out = "./output.ll";

  int rc = swift_irgen_adapter_compile(source, module, out);
  if (rc != 0) {
    std::cerr << "adapter compile failed: " << rc << "\n";
    return 1;
  }

  std::ifstream in(out);
  std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  if (content.find("define") == std::string::npos) {
    std::cerr << "IR output missing 'define'\n";
    return 2;
  }

  std::cout << "adapter lib API test passed\n";
  return 0;
}
CPP

$CXX -std=c++17 \
  "$BUILD_DIR/harness.cpp" \
  -I"$ROOT_DIR/Native/SwiftIRGenAdapter" \
  -L"$BUILD_DIR" -lSwiftFrontendAdapter \
  -Wl,--export-dynamic \
  -Wl,-rpath,"$BUILD_DIR" \
  -o "$BUILD_DIR/harness"

(
  cd "$BUILD_DIR"
  ./harness
)

echo "完了: Linux frontend lib API 実行テスト"
