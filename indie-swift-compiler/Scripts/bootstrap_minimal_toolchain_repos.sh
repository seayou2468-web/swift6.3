#!/usr/bin/env bash
set -euo pipefail

# このリポジトリ内の最小構成JSONを使い、必要最小限リポジトリのみ取得する。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
WORKSPACE_DIR="${2:-$ROOT_DIR/.toolchain-workspace}"

MIN_CONFIG="$ROOT_DIR/Config/minimal-update-checkout-config.json"
if [[ ! -f "$MIN_CONFIG" ]]; then
  echo "エラー: 最小設定が見つかりません: $MIN_CONFIG"
  exit 1
fi

python3 "$ROOT_DIR/Tools/sync_toolchain_repos.py" \
  --config "$MIN_CONFIG" \
  --scheme "$SCHEME" \
  --workspace "$WORKSPACE_DIR"

echo "最小ツールチェーン取得完了: $WORKSPACE_DIR"
