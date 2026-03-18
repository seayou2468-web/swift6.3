#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.build/pipeline-verify"
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

if [[ -z "$LLVM_AS" || -z "$LLC" || -z "$CLANG" ]]; then
  echo "llvm-as / llc / clang のいずれかが見つかりません"
  exit 1
fi

cat > "$WORK_DIR/input.swift" <<'SWIFT'
@_cdecl("main")
public func appMain() -> Int32 {
  return 42
}
SWIFT

FRONTEND_ARGS=(-frontend -emit-ir "$WORK_DIR/input.swift" -module-name PipelineVerify -o "$WORK_DIR/output.ll")
if [[ -n "$SDK_PATH" ]]; then
  FRONTEND_ARGS+=(-sdk "$SDK_PATH")
fi
"$SWIFT_FRONTEND" "${FRONTEND_ARGS[@]}"

if ! rg -q "define .*@main" "$WORK_DIR/output.ll"; then
  echo "swift-frontend が main 関数のIRを生成できませんでした"
  exit 1
fi

"$LLVM_AS" "$WORK_DIR/output.ll" -o "$WORK_DIR/output.bc"
"$LLC" -filetype=obj "$WORK_DIR/output.bc" -o "$WORK_DIR/output.o"
"$CLANG" "$WORK_DIR/output.o" -o "$WORK_DIR/app"

"$WORK_DIR/app"
STATUS=$?
if [[ $STATUS -ne 42 ]]; then
  echo "期待値 42 と不一致: $STATUS"
  exit 1
fi

echo "検証成功: Swift -> swift-frontend -> LLVM -> 実行 (exit=42)"
