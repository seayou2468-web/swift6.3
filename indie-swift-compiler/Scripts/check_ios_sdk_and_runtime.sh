#!/usr/bin/env bash
set -euo pipefail

SWIFT_FRONTEND="${SWIFT_FRONTEND_PATH:-$(xcrun --find swift-frontend 2>/dev/null || true)}"
DOCUMENTS_SDK="${HOME}/Documents/sdk"
SDK_PATH="${SWIFT_SDK_PATH:-}"
if [[ -z "$SDK_PATH" && -d "$DOCUMENTS_SDK" ]]; then
  SDK_PATH="$DOCUMENTS_SDK"
fi
if [[ -z "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
fi
TOOLCHAIN_BIN="$(dirname "$SWIFT_FRONTEND")"
TOOLCHAIN_ROOT="$(cd "$TOOLCHAIN_BIN/.." && pwd)"
RUNTIME_DIR="${SWIFT_RUNTIME_DIR:-$TOOLCHAIN_ROOT/lib/swift}"

if [[ -z "$SWIFT_FRONTEND" ]]; then
  echo "swift-frontend が見つかりません"
  exit 1
fi
if [[ -z "$SDK_PATH" ]]; then
  echo "iPhoneOS SDK が見つかりません"
  exit 1
fi
if [[ ! -d "$RUNTIME_DIR" ]]; then
  echo "Swift runtime ディレクトリが見つかりません: $RUNTIME_DIR"
  exit 1
fi

echo "swift-frontend: $SWIFT_FRONTEND"
echo "documents sdk: $DOCUMENTS_SDK"
echo "iOS SDK: $SDK_PATH"
echo "Swift runtime dir: $RUNTIME_DIR"

find "$RUNTIME_DIR" -maxdepth 2 -type f \( -name 'libswiftCore*' -o -name 'libswift_Concurrency*' \) | head -n 20
