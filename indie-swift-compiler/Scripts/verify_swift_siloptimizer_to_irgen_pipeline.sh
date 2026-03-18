#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/siloptimizer-irgen-verify"
mkdir -p "$WORK_DIR"

SWIFT_FRONTEND="${SWIFT_FRONTEND_PATH:-}"
if [[ -z "$SWIFT_FRONTEND" ]]; then
  SWIFT_FRONTEND="$(xcrun --find swift-frontend 2>/dev/null || true)"
fi
if [[ -z "$SWIFT_FRONTEND" ]]; then
  SWIFT_FRONTEND="$(command -v swift-frontend || true)"
fi

if [[ -z "$SWIFT_FRONTEND" ]]; then
  echo "swift-frontend が見つかりません"
  exit 1
fi

SDK_PATH="${SWIFT_SDK_PATH:-}"
if [[ -z "$SDK_PATH" && -d "${HOME}/Documents/sdk" ]]; then
  SDK_PATH="${HOME}/Documents/sdk"
fi

LLVM_AS="${LLVM_AS_PATH:-$(command -v llvm-as || true)}"
LLC="${LLC_PATH:-$(command -v llc || true)}"
CLANG="${CLANG_PATH:-$(command -v clang || true)}"

if [[ -z "$CLANG" ]]; then
  echo "clang が見つかりません"
  exit 1
fi

cat > "$WORK_DIR/input.swift" <<'SWIFT'
@inline(never)
public func increment(_ x: Int) -> Int {
  return x + 1
}

@_cdecl("main")
public func appMain() -> Int32 {
  return Int32(increment(41))
}
SWIFT

COMMON_ARGS=(-frontend -parse-as-library "$WORK_DIR/input.swift" -module-name PipelineVerify)
if [[ -n "$SDK_PATH" ]]; then
  COMMON_ARGS+=(-sdk "$SDK_PATH")
fi

"$SWIFT_FRONTEND" "${COMMON_ARGS[@]}" -emit-silgen -o "$WORK_DIR/raw.sil"
"$SWIFT_FRONTEND" "${COMMON_ARGS[@]}" -O -emit-sil \
  -save-optimization-record \
  -save-optimization-record-path "$WORK_DIR/full-optimizer.opt.yaml" \
  -o "$WORK_DIR/optimized.sil"
"$SWIFT_FRONTEND" "${COMMON_ARGS[@]}" -O -disable-sil-perf-optzns -emit-sil \
  -save-optimization-record \
  -save-optimization-record-path "$WORK_DIR/no-perf.opt.yaml" \
  -o "$WORK_DIR/no-perf.sil"

if ! head -n 1 "$WORK_DIR/raw.sil" | grep -q "sil_stage raw"; then
  echo "raw SIL の生成に失敗しました"
  exit 1
fi

if ! head -n 1 "$WORK_DIR/optimized.sil" | grep -q "sil_stage canonical"; then
  echo "最適化済み SIL の生成に失敗しました"
  exit 1
fi

if ! grep -q "Pass: *sil-inliner" "$WORK_DIR/full-optimizer.opt.yaml"; then
  echo "Full SILOptimizer の最適化記録に sil-inliner が見つかりません"
  exit 1
fi

if grep -q "Pass: *sil-inliner" "$WORK_DIR/no-perf.opt.yaml"; then
  echo "disable-sil-perf-optzns 指定時にも sil-inliner が実行されています"
  exit 1
fi

"$SWIFT_FRONTEND" -frontend -parse-sil -emit-ir "$WORK_DIR/optimized.sil" -module-name PipelineVerify -o "$WORK_DIR/output.ll"

if ! rg -q "define .*@main" "$WORK_DIR/output.ll"; then
  echo "最適化済み SIL から main 関数のIRが生成できませんでした"
  exit 1
fi

if [[ -n "$LLVM_AS" && -n "$LLC" ]]; then
  "$LLVM_AS" "$WORK_DIR/output.ll" -o "$WORK_DIR/output.bc"
  "$LLC" -filetype=obj "$WORK_DIR/output.bc" -o "$WORK_DIR/output.o"
  "$CLANG" "$WORK_DIR/output.o" -o "$WORK_DIR/app"
else
  echo "llvm-as/llc がないため clang -x ir で直接リンクします"
  "$CLANG" -x ir "$WORK_DIR/output.ll" -o "$WORK_DIR/app"
fi

set +e
"$WORK_DIR/app"
STATUS=$?
set -e
if [[ $STATUS -ne 42 ]]; then
  echo "期待値 42 と不一致: $STATUS"
  exit 1
fi

echo "検証成功: Swift -> Full SILOptimizer -> optimized SIL -> IRGen -> LLVM -> 実行 (exit=42)"
