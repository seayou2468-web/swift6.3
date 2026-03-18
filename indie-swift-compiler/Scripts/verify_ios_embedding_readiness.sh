#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/Artifacts}"
UNIFIED_XC="$OUT_DIR/SwiftToolchainKit.xcframework"
RUNTIME_XC="$OUT_DIR/SwiftRuntimeCore.xcframework"
STRICT_MODE="${VERIFY_IOS_EMBEDDING_STRICT:-0}"

warn_or_fail() {
  local msg="$1"
  if [[ "$STRICT_MODE" == "1" ]]; then
    echo "エラー: $msg"
    exit 1
  fi
  echo "WARN: $msg"
}

if [[ ! -d "$UNIFIED_XC" ]]; then
  warn_or_fail "必須成果物不足: $UNIFIED_XC"
  echo "iOS組み込み readiness 検証は警告モードで継続しました"
  exit 0
fi

mapfile -t frontend_libs < <(find "$UNIFIED_XC" -type f -name 'libSwiftFrontend.a' | sort)
if [[ ${#frontend_libs[@]} -eq 0 ]]; then
  warn_or_fail "unified xcframework に libSwiftFrontend.a が含まれていません"
fi

if [[ ${#frontend_libs[@]} -gt 0 ]]; then
  nm_cmd=(nm -gU)
  if ! nm -gU "${frontend_libs[0]}" >/dev/null 2>&1; then
    nm_cmd=(nm -g)
  fi

  for lib in "${frontend_libs[@]}"; do
    if ! "${nm_cmd[@]}" "$lib" 2>/dev/null | grep -q 'swift_frontend_embedded_compile'; then
      warn_or_fail "$lib に swift_frontend_embedded_compile が含まれていません"
      continue
    fi
    echo "OK: embedded frontend symbol in $lib"
  done
fi

mapfile -t runtime_libs < <(find "$UNIFIED_XC" -type f -name 'libswiftCore.a' | sort)
if [[ ${#runtime_libs[@]} -gt 0 ]]; then
  echo "OK: unified xcframework に Swift runtime を同梱済み"
  printf '  %s\n' "${runtime_libs[@]}"
elif [[ -d "$RUNTIME_XC" ]]; then
  echo "OK: runtime は standalone xcframework として利用可能"
  echo "  $RUNTIME_XC"
else
  warn_or_fail "Swift runtime が unified/standalone のいずれにも見つかりません"
fi

echo "iOS組み込み readiness 検証完了 (strict=$STRICT_MODE)"
