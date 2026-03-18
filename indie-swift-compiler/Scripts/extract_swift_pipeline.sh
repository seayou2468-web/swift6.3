#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "使い方: $0 <swift-repo-path>"
  exit 1
fi

SWIFT_REPO="$(cd "$1" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Vendor/SwiftFrontendExtract"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

copy_if_exists() {
  local rel="$1"
  if [[ -f "$SWIFT_REPO/$rel" ]]; then
    mkdir -p "$OUT_DIR/$(dirname "$rel")"
    cp "$SWIFT_REPO/$rel" "$OUT_DIR/$rel"
    echo "copied: $rel"
  else
    echo "skip (not found): $rel"
  fi
}

# Swift -> LLVM IR 変換の主要導線（参照専用）
copy_if_exists "lib/FrontendTool/FrontendTool.cpp"
copy_if_exists "lib/IRGen/IRGen.cpp"
copy_if_exists "lib/IRGen/IRGenModule.cpp"
copy_if_exists "lib/IRGen/GenCall.cpp"
copy_if_exists "lib/IRGen/GenDecl.cpp"
copy_if_exists "lib/IRGen/GenFunc.cpp"
copy_if_exists "lib/IRGen/GenMeta.cpp"
copy_if_exists "lib/IRGen/GenProto.cpp"
copy_if_exists "lib/IRGen/GenType.cpp"
copy_if_exists "include/swift/IRGen/IRGen.h"
copy_if_exists "include/swift/IRGen/IRGenPublic.h"

# Swift SIL middle層（SIL最適化導線、参照専用）
copy_if_exists "include/swift/SIL/SILModule.h"
copy_if_exists "include/swift/SIL/SILFunction.h"
copy_if_exists "include/swift/SILOptimizer/PassManager/PassManager.h"
copy_if_exists "lib/SIL/IR/SILModule.cpp"
copy_if_exists "lib/SIL/IR/SILFunction.cpp"
copy_if_exists "lib/SIL/Verifier/SILVerifier.cpp"
copy_if_exists "lib/SILOptimizer/PassManager/PassManager.cpp"
copy_if_exists "lib/SILOptimizer/PassManager/Passes.cpp"
copy_if_exists "lib/SILOptimizer/Transforms/PerformanceInliner.cpp"

cat > "$OUT_DIR/EXTRACTED.md" <<MARKDOWN
# Extracted Swift Frontend References

このディレクトリは、Swift本家リポジトリから「Swift AST/SIL から LLVM IR 生成」に
関与する主要導線を追うための参照用コピーです。

- この新規コンパイラのビルドには **使用しません**。
- 依存切り離しのため、MiniSwiftCompilerCore は swift-frontend adapter 経路で動作します。
MARKDOWN

echo "抽出完了: $OUT_DIR"
