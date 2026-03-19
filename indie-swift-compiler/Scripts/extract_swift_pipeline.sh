#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
SWIFT_REPO="$REPO_ROOT/swift"
OUT_DIR="$ROOT_DIR/Vendor/SwiftFrontendExtract"

if [[ ! -d "$SWIFT_REPO" ]]; then
  echo "swift checkout not found in repository: $SWIFT_REPO"
  exit 1
fi

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

# swift-frontend 実行ファイルや driver 層は抽出対象に含めない（直接内蔵するのは中間表現生成までの層のみ）
FORBIDDEN_PATHS=(
  "bin/swift-frontend"
  "libexec/swift/swift-frontend"
  "lib/Frontend"
  "include/swift/Frontend"
  "tools/driver"
)

verify_forbidden_not_extracted() {
  for forbidden in "${FORBIDDEN_PATHS[@]}"; do
    if [[ -e "$OUT_DIR/$forbidden" ]]; then
      echo "forbidden component was extracted: $forbidden"
      exit 1
    fi
  done
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
copy_if_exists "include/swift/Sema/ConstraintSystem.h"
copy_if_exists "lib/Sema/TypeCheckDecl.cpp"
copy_if_exists "lib/Sema/TypeCheckExpr.cpp"
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
copy_if_exists "include/swift/IRGen/IRGenSILPasses.h"
copy_if_exists "include/swift/IRGen/IRGenPublic.h"

# Swift SIL middle層（SIL最適化導線、独自コンパイラへ直接同梱）
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

verify_forbidden_not_extracted

cat > "$OUT_DIR/EXTRACTED.md" <<'MARKDOWN'
# Extracted Swift Embedded Compiler Components

このディレクトリは、このリポジトリ直下の `swift/` ツリーから Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を
直接コピーして、独自コンパイラに内蔵するための作業コピーです。

- 外部の swift リポジトリパス指定は不要です。
- `Scripts/extract_swift_pipeline.sh` は常にこのリポジトリ直下の `swift/` からコピーします。
- 新規コンパイラは swift-frontend 実行ファイルではなく、ここでコピーした層を直接内蔵する方針です。
- `swift-frontend` 実行ファイル / Frontend / Driver 層は抽出禁止としてスクリプトで検証しています。
MARKDOWN

echo "repo-local copy complete: $OUT_DIR"
