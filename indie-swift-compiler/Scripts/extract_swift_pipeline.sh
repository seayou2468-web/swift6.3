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

# Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen の完全抽出（内蔵前提）
copy_if_exists "include/swift/Parse/Parser.h"
copy_if_exists "lib/Parse/ParseDecl.cpp"
copy_if_exists "lib/Parse/ParseExpr.cpp"
copy_if_exists "lib/Parse/ParseStmt.cpp"
copy_if_exists "include/swift/AST/ASTContext.h"
copy_if_exists "include/swift/AST/Module.h"
copy_if_exists "lib/AST/ASTContext.cpp"
copy_if_exists "lib/AST/Module.cpp"
copy_if_exists "include/swift/Sema/TypeChecker.h"
copy_if_exists "lib/Sema/TypeCheckDecl.cpp"
copy_if_exists "lib/Sema/TypeCheckExpr.cpp"
copy_if_exists "include/swift/SILGen/SILGen.h"
copy_if_exists "lib/SILGen/SILGen.cpp"
copy_if_exists "lib/SILGen/SILGenFunction.cpp"
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
copy_if_exists "include/swift/AST/SILOptimizerRequests.h"
copy_if_exists "include/swift/AST/SILOptimizerTypeIDZone.def"
copy_if_exists "lib/SILOptimizer/SILOptimizer.cpp"
copy_if_exists "lib/SIL/IR/SILModule.cpp"
copy_if_exists "lib/SIL/IR/SILFunction.cpp"
copy_if_exists "lib/SIL/Verifier/SILVerifier.cpp"
copy_if_exists "lib/SILOptimizer/PassManager/SILOptimizerRequests.cpp"
copy_if_exists "lib/SILOptimizer/PassManager/PassManager.cpp"
copy_if_exists "lib/SILOptimizer/PassManager/Passes.cpp"
copy_if_exists "lib/SILOptimizer/Transforms/PerformanceInliner.cpp"

cat > "$OUT_DIR/EXTRACTED.md" <<MARKDOWN
# Extracted Swift Embedded Compiler Components

このディレクトリは、Swift本家リポジトリから Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を
完全抽出して独自コンパイラに内蔵するための作業コピーです。

- 抽出したコンポーネントの使用を許可します。
- 新規コンパイラは swift-frontend 実行ファイルではなく、ここで抽出した層を直接内蔵する方針です。
MARKDOWN

echo "抽出完了: $OUT_DIR"
