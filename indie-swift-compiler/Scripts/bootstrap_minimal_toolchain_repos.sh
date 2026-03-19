#!/usr/bin/env bash
set -euo pipefail

# このリポジトリ内の最小構成JSONを使い、必要最小限リポジトリのみ取得する。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${1:-release/6.3}"
WORKSPACE_DIR="${2:-$ROOT_DIR/.toolchain-workspace}"
MANIFEST_PATH="$WORKSPACE_DIR/.sync-manifest.json"

MIN_CONFIG="$ROOT_DIR/Config/minimal-update-checkout-config.json"
if [[ ! -f "$MIN_CONFIG" ]]; then
  echo "エラー: 最小設定が見つかりません: $MIN_CONFIG"
  exit 1
fi

mkdir -p "$WORKSPACE_DIR"

EXPECTED_MANIFEST="$(python3 - <<PY
import hashlib
import json
from pathlib import Path

config_path = Path("$MIN_CONFIG")
config = json.loads(config_path.read_text(encoding="utf-8"))
scheme_name = "$SCHEME"
scheme = config.get("branch-schemes", {}).get(scheme_name)
if not scheme:
    raise SystemExit(f"scheme not found: {scheme_name}")
manifest = {
    "config_sha256": hashlib.sha256(config_path.read_bytes()).hexdigest(),
    "repos": scheme.get("repos", {}),
    "scheme": scheme_name,
}
print(json.dumps(manifest, sort_keys=True, separators=(",", ":")))
PY
)"

mapfile -t REQUIRED_REPOS < <(python3 - <<PY
import json
from pathlib import Path
config = json.loads(Path("$MIN_CONFIG").read_text(encoding="utf-8"))
for name in sorted(config.get("repos", {}).keys()):
    print(name)
PY
)

if [[ "${FORCE_TOOLCHAIN_SYNC:-0}" != "1" && -f "$MANIFEST_PATH" ]]; then
  CURRENT_MANIFEST="$(tr -d '\n' < "$MANIFEST_PATH")"
  missing_repo=0
  for repo in "${REQUIRED_REPOS[@]}"; do
    if [[ ! -d "$WORKSPACE_DIR/$repo/.git" ]]; then
      missing_repo=1
      break
    fi
  done
  if [[ "$missing_repo" == "0" && "$CURRENT_MANIFEST" == "$EXPECTED_MANIFEST" ]]; then
    echo "toolchain workspace cache hit: requested scheme/config unchanged, sync skipped"
    echo "最小ツールチェーン取得完了: $WORKSPACE_DIR"
    exit 0
  fi
fi

python3 "$ROOT_DIR/Tools/sync_toolchain_repos.py" \
  --config "$MIN_CONFIG" \
  --scheme "$SCHEME" \
  --workspace "$WORKSPACE_DIR"

printf '%s\n' "$EXPECTED_MANIFEST" > "$MANIFEST_PATH"

echo "最小ツールチェーン取得完了: $WORKSPACE_DIR"
